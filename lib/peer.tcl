## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::peer 0
# Meta author      {Andreas Kupries}
# Meta category    ?
# Meta description ?
# Meta location    https://core.tcl-lang.org/akupries/fx
# Meta platform    tcl
# Meta require     ?
# Meta subject     ?
# Meta summary     ?
# @@ Meta End

# # ## ### ##### ######## ############# ######################

package require Tcl 8.5
package require cmdr::color
package require debug
package require debug::caller
package require fileutil
package require interp
package require linenoise
package require textutil::adjust
package require try
package require base64

package require fx::fossil
package require fx::mailer
package require fx::mgr::config
package require fx::mgr::map
package require fx::table
package require fx::util

# # ## ### ##### ######## ############# ######################

namespace eval ::fx {
    namespace export peer
    namespace ensemble create
}
namespace eval ::fx::peer {
    namespace export \
	list add remove add-git remove-git exchange \
	state-dir state-reset state-clear \
	export import init
    namespace ensemble create

    namespace import ::cmdr::color
    namespace import ::fx::fossil
    namespace import ::fx::mailer
    namespace import ::fx::mgr::config
    namespace import ::fx::mgr::map
    namespace import ::fx::util

    namespace import ::fx::table::do
    rename do table
}

# # ## ### ##### ######## ############# ######################

debug level  fx/peer
debug prefix fx/peer {[debug caller] | }

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::list {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    set map [Get $config]
    # dict: "fossil" + url + area -> direction
    #       "git" + url           -> list (last-uuid, mach)

    # Restructure the map to be indexed by url, and canonicalize the
    # associated data for the table.
    set tmap {}
    dict for {type spec} $map {
	switch -exact -- $type {
	    fossil {
		dict for {url espec} $spec {
		    set etype $type
		    dict for {area dir} [util dictsort $espec] {
			dict lappend tmap $url [::list $etype $dir $area {} {}]
			# Drop type information in multiple rows of the same url
			set etype {}
		    }
		}
	    }
	    git {
		dict for {url gspec} $spec {
		    lassign $gspec last mach
		    dict lappend tmap $url [::list $type push content $last $mach]
		}
	    }
	    default {
		error "Bad peer type \"$type\", expected one of fossil, or git"
	    }
	}
    }

    # Show the table
    [table t {Url Type Flow Area Last Machine} {
	foreach {u speclist} [util dictsort $tmap] {
	    foreach spec [lsort -dict $speclist] {
		$t add $u {*}$spec
		# Drop the url in multiple rows of the same url.
		set u {}
	    }
	}
    }] show
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::add {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    set url  [$config @peer]
    set dir  [$config @direction]
    set area [$config @area]

    puts -nonewline "  Adding fossil \"$url $dir $area\" ... "
    flush stdout

    AddFossil $url $dir $area
    return
}

proc ::fx::peer::remove {config} {
    debug.fx/peer {}
    fossil show-repository-location

    set url  [$config @peer]
    set dir  [$config @direction]
    set area [$config @area]

    puts -nonewline "  Removing fossil \"$url $dir $area\" ... "
    flush stdout

    set peers [map get fx@peer@fossil]

    if {![dict exists $peers $url]} {
	puts [color note {No change, ignored}]
	return
    }

    # Drop areas ...
    set spec [dict get $peers $url]

    if {![dict exists $spec $area]} {
	puts [color note {No change, ignored}]
	return
    }

    # Merge directions ...
    variable dremove
    set old [dict get $spec $area]
    set new [dict get $dremove $old $dir]

    debug.fx/peer { Have $area => $old}
    debug.fx/peer { Drop          $dir}
    debug.fx/peer { Keeping       $new}

    if {$new eq $old} {
	puts [color note {No change, ignored}]
	return
    }

    if {$new eq {}} {
	# No directions left for the area, drop entire area.
	debug.fx/peer {drop entire $area}
	dict unset spec $area
    } else {
	# Change to reduced directions of the area.
	dict set spec $area $new
    }

    debug.fx/peer {new spec = ($spec)}

    if {![dict size $spec]} {
	# Drop entirely...
	debug.fx/peer {drop entire $url}
	map remove1 fx@peer@fossil $url
	puts [color good OK]
	return
    }

    # Change stored spec.
    debug.fx/peer {save changed}
    fossil repository transaction {
	map remove1 fx@peer@fossil $url
	map add1    fx@peer@fossil $url $spec
    }

    puts [color good OK]
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::add-git {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    set url [$config @peer]
    set mach {}
    if {[$config @machine set?]} {
	set mach [$config @machine]
    }

    puts -nonewline "  Adding git \"$url push content\" ... "
    flush stdout

    AddGit $url {} $mach
    return
}

proc ::fx::peer::remove-git {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    set url [$config @peer]

    puts -nonewline "  Removing git \"$url push content\" ... "
    flush stdout

    set peers [map get fx@peer@git]

    if {![dict exists $peers $url]} {
	puts [color note {No change, ignored}]
	return
    }

    # TODO: Document the git data structures.

    map remove1 fx@peer@git $url
    puts [color good OK]
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::state-dir {config} {
    debug.fx/peer {}
    fossil show-repository-location

    if {[$config @dir set?]} {
	# Specified, set value.
	config set-local fx-aku-peer-git-state [$config @dir]
    }

    # Show current value, possibly set above.
    puts [Statedir]
    return
}

proc ::fx::peer::state-reset {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    set state [Statedir]
    if {[IsState $state]} {
	if {[MyState $state _ _]} {
	    puts "  Drop tracked uuid from state [color note $state]"
	    GitDropLast $state
	} else {
	    puts "  [color error {Not touching}] non-owned state [color note $state]"
	}
    } else {
	puts "  Ignoring non-state [color note $state]"
    }

    GitClearAll

    puts [color good OK]
    return
}

proc ::fx::peer::state-clear {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    set state [Statedir]
    if {[IsState $state]} {
	if {[MyState $state _ _]} {
	    puts "  Discard state [color note $state]"
	    file delete -force $state
	} else {
	    puts "  [color error {Not touching}] non-owned state [color note $state]"
	}
    } else {
	puts "  Ignoring non-state [color note $state]"
    }

    GitClearAll

    puts [color good OK]
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::exchange {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    # See also note.tcl, ProjectInfo.
    set location [mailer get location]
    set	project  [mailer get project-name]

    set map [Get $config]
    # dict: "fossil" + url + area -> direction
    #       "git" + url           -> list (last-uuid, mach)

    # Note: The dictsort means that fossil peers are handled before
    # git peers. That is good because it means that any new content
    # pulled from one or more of the fossil peers will be pushed
    # immediately to the git peers, instead of getting delayed by one
    # exchange cycle.

    dict for {type spec} [util dictsort $map] {
	switch -exact -- $type {
	    fossil {
		dict for {url espec} [util dictsort $spec] {
		    dict for {area dir} [util dictsort $espec] {
			# Exchange data for area, per chosen direction.
			# Invokes regular fossil to perform the action.
			puts "Exchange [string repeat _ 40]"
			puts "Fossil [color note $url]"
			puts "[string totitle $dir] $area ..."

			fossil exchange $url $area $dir
			puts [color good OK]
		    }
		}
	    }
	    git {
		GitCycle $project $location $spec
	    }
	    default {
		error "Bad peer type \"$type\", expected one of fossil, or git"
	    }
	}
    }
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::export {config} {
    debug.fx/peer {}
    fossil show-repository-location
    init

    lappend data "\# fx peer export @ [clock format [clock seconds]]"
    dict for {url dlist} [map get fx@peer@fossil] {
	foreach {area dir} $dlist {
	    lappend data [::list fossil $area $dir $url]
	}
    }
    dict for {url spec} [map get fx@peer@git] {
	lappend data [::list git $url {*}$spec]
    }

    set    chan [util open [$config @output]]
    puts  $chan [join $data \n]
    close $chan
    return
}

proc ::fx::peer::import {config} {
    debug.fx/peer {}
    fossil show-repository-location

    set extend [$config @extend]

    set input [$config @input]
    set data [read $input]
    $config @input forget

    # Run the import script in a safe interpreter with just the import
    # commands. This generates internal data structures from which we
    # then create the peering links again.
    variable imported {}

    set i [interp::createEmpty]
    $i alias fossil ::fx::peer::IFossil
    $i alias git    ::fx::peer::IGit
    $i eval $data
    interp delete $i

    if {!$extend} {
	puts [color warning "Import replaces all existing peers ..."]
	# Inlined delete of all peers
	map delete fx@peer@fossil
	map delete fx@peer@git
    } else {
	puts [color note "Import keeps the existing peers ..."]

        if {![llength $imported]} {
	    puts [color note {No peers to import}]
	    return
	}
    }

    puts "New peers ..."
    init
    foreach {type url details} $imported {
	puts -nonewline "  Importing $type $url ($details) ... "
	flush stdout

	switch -exact -- $type {
	    fossil { AddFossil $url {*}$details }
	    git    { AddGit    $url {*}$details }
	    default {
		error "Bad peer type \"$type\", expected one of fossil, or git"
	    }
	}
    }
    return
}

proc ::fx::peer::IFossil {area dir url} {
    debug.fx/peer {}
    variable imported
    lappend  imported fossil $url [::list $dir $area]
    return
}

proc ::fx::peer::IGit {url last} {
    debug.fx/peer {}
    variable imported
    lappend  imported git $url $last
    return
}

# # ## ### ##### ######## ############# ######################

proc ::fx::peer::AddFossil {url dir area} {
    debug.fx/peer {}

    set peers [map get fx@peer@fossil]

    if {![dict exists $peers $url]} {
	# New peer
	map add1 fx@peer@fossil $url [::list $area $dir]
	puts [color good OK]
	return
    }

    # Merge areas ...
    set spec [dict get $peers $url]

    if {![dict exists $spec $area]} {
	# New area in known peer
	dict set spec $area $dir
	fossil repository transaction {
	    map remove1 fx@peer@fossil $url
	    map add1    fx@peer@fossil $url $spec
	}
	puts [color good OK]
	return
    }

    # Merge directions for known area in known peer ...
    variable dadd
    set old [dict get $spec $area]
    set new [dict get $dadd $old $dir]

    if {$new eq $old} {
	puts [color note {No change, ignored}]
	return
    }

    puts -nonewline [color note "upgraded to $new "]
    flush stdout

    dict set spec $area $new
    fossil repository transaction {
	map remove1 fx@peer@fossil $url
	map add1    fx@peer@fossil $url $spec
    }

    puts [color good OK]
    return
}

proc ::fx::peer::AddGit {url last {mach {}}} {
    debug.fx/peer {}

    set peers [map get fx@peer@git]

    if {[dict exists $peers $url]} {
	puts [color note {No change, ignored}]
	return
    }

    if {($mach eq "integrated") && ([package vcompare [FossilVersion] 2.9] < 0)} {
	puts [color error {Integrated machine not supported by available fossil. Need version 2.9+.}]
	puts [color note {Ignored}]
	return
    }
    
    if {[dict size $peers]} {
	set themach [lindex $peers 1]
	if {$themach ne $mach} {
	    if {$mach eq {}} {
		# Automatic adapts to existing machinery
		set mach $themach
	    } else {
		puts [color error {Machine mismatch.}]
		puts [color note {Ignored}]
		return
	    }
	}
    }
    
    map add1 fx@peer@git $url [::list {} $mach]
    puts [color good OK]
    return
}

# # ## ### ##### ######## ############# ######################
## Internal import support commands.

proc ::fx::peer::Statedir {} {
    debug.fx/peer {}
    return [config get-with-default \
		fx-aku-peer-git-state \
		[fossil repository-location].peer-state]
}

proc ::fx::peer::Claim {statedir pcode} {
    debug.fx/peer {}
    fileutil::writeFile $statedir/owner $pcode
    return
}

proc ::fx::peer::MarkerIntegrated {statedir} {
    debug.fx/peer {}
   return $statedir/fossil-2.9-integrated-git-export
}

proc ::fx::peer::MarkerOrchestrated {statedir} {
    debug.fx/peer {}
   return $statedir/git/git-daemon-export-ok
}

proc ::fx::peer::MarkIntegrated {statedir} {
    debug.fx/peer {}
    fileutil::touch [MarkerIntegrated $statedir]
    return
}

proc ::fx::peer::MarkOrchestrated {statedir} {
    debug.fx/peer {}
    fileutil::touch [MarkerOrchestrated $statedir]
    return
}

proc ::fx::peer::IsIntegrated {statedir} {
    set marker [MarkerIntegrated $statedir]
    expr {[file exists $marker] && [file isfile $marker]}
}

proc ::fx::peer::IsOrchestrated {statedir} {
    set marker [MarkerOrchestrated $statedir]
    expr {[file exists $marker] && [file isfile $marker]}
}

proc ::fx::peer::IsState {statedir} {
    debug.fx/peer {}
    return [expr {[IsIntegrated   $statedir] ||
		  [IsOrchestrated $statedir]}]
}

proc ::fx::peer::MyState {statedir pv ov} {
    upvar 1 $pv pcode $ov owner
    debug.fx/peer {}
    set pcode [config get-local project-code]
    set owner [string trim [fileutil::cat $statedir/owner]]
    return [expr {$pcode eq $owner}]
}

proc ::fx::peer::IsLocked {statedir rv} {
    debug.fx/peer {}
    set locked [file exists $statedir/lock]
    if {$locked} {
	upvar 1 $rv reason
	set reason [string trim [fileutil::cat $statedir/lock]]
    }
    debug.fx/peer {locked = $locked}
    return $locked
}

proc ::fx::peer::Mail {statedir reason} {
    debug.fx/peer {}
    fileutil::writeFile $statedir/lock $reason
    # This happens only once per problem, because afterward the lock
    # file prevents fx from getting here until the lock is removed.
    ::fx::mail-error $reason
    return
}

proc ::fx::peer::GitCycle {project location spec} {
    debug.fx/peer {}
    set state [Statedir]
    
    GitSetup $state $project $location [lindex $spec 1]

    if {[IsIntegrated $state]} {
	# Run the fossil/git orchestration integrated in fossil itself.

	dict for {url _} [util dictsort $spec] {
	    lassign $_ last mach
	    # Assert: mach == integrated
	    
	    puts "Exchange [string repeat _ 40]"
	    puts "Git [color note $url]"
	    puts "Push content ..."
	    puts "  Machine @ $mach"
	    
	    set curl [base64::encode -maxlen 0 $url]
	    set src  [fossil repository-location]

	    # The integrated orchestration uses separate local git
	    # repositories, one per peer.
	    Run fossil git export $state/m_$curl -R $src --autopush $url \
		|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}
	    # https://username:password@github.com/username/project.git

	    # TODO: Consider catching errors here, and going
	    #       to the next remote, in case of multiple remotes.

	    puts [color good OK]
	}

	return
    }

    if {[IsOrchestrated $state]} {
	# Export using our own orchestration of fossil and git.

	set current [GitImport $state $project $location]
	dict for {url _} [util dictsort $spec] {
	    lassign $_ last mach
	    # Assert: mach == orchestrated
	    
	    puts "Exchange [string repeat _ 40]"
	    puts "Git [color note $url]"
	    puts "Push content ..."
	    puts "  State   @ $current"
	    puts "  Remote  @ $last"
	    puts "  Machine @ $mach"

	    # Skip destinations which are uptodate.
	    if {$last eq $current} {
		puts [color note "  No new commits"]
		puts [color good OK]
		continue
	    }

	    # TODO: Consider catching errors here, and going
	    #       to the next remote, in case of multiple remotes.

	    GitPush $state $url $current $mach
	    puts [color good OK]
	}

	return
    }

    # Neither Integrated, nor Orchestrated. That must not happen.
    return -code error \
	"Bad git state setup, neither integrated nor orchestrated"
}

proc ::fx::peer::GitClearAll {} {
    debug.fx/peer {}
    fossil repository transaction {
	set peers [map get fx@peer@git]
	dict for {url spec} $peers {
	    lassign $spec last mach
	    puts "  Cleared tracked uuid for git peer [color note $url]"
	    GitClear $url $mach
	}
    }
    debug.fx/peer {[GitRemotes]}
    return
}

proc ::fx::peer::GitClear {url mach} {
    debug.fx/peer {}
    map remove1 fx@peer@git $url
    map add1    fx@peer@git $url [::list {} $mach]
    return
}

proc ::fx::peer::GitRemotes {} {
    set lines {}
    fossil repository transaction {
	set peers [map get fx@peer@git]
	dict for {url spec} $peers {
	    lassign $spec last mach
	    append lines "Remote " $url " = (" $last "), $mach\n"
	}
    }
    return $lines
}

# taken from old setup-import script.
proc ::fx::peer::GitSetup {statedir project location mach} {
    debug.fx/peer {}

    puts "Exchange [string repeat _ 40]"
    puts "Git State Directory"

    if {[IsState $statedir]} {
	debug.fx/peer {/initialized}
	puts "  Ready at [color note $statedir]."

	# A ready directory may still belong to a different
	# project. Check this.

	if {![MyState $statedir pcode owner]} {
	    puts [color error "  Error: Claimed by project \"$owner\""]
	    puts [color error "  Error: Which is not us    \"$pcode\""]
	    # Abort self, and caller (exchange).
	    return -code return
	}
	if {[IsLocked $statedir reason]} {
	    puts [color error "  Locked: $reason"]
	    return -code return
	}
	puts [color good OK]
	return
    }

    set pcode [config get-local project-code]

    puts "  Initialize at [color note $statedir]."

    # State directory is not initialized. Do it now.
    # Drop anything else which may existed in its place.
    debug.fx/peer {initialize now}

    # The git state is a sub-directory of the main state directory
    # This allows us to put other (more transient) state as a sibling
    # of the git directory while not requiring additional path
    # configuration keys.

    if {$mach eq {}} {
	if {[package vcompare [FossilVersion] 2.9] >= 0} {
	    # Fossil 2.9, or higher. We can use the integrated `fossil
	    # git export` command. It orchestrates everything by itself.
	    set mach integrated
	} else {
	    set mach orchestrated
	}
    }
    
    if {$mach eq "integrated"} {
	debug.fx/peer {initialize integrated}

	MarkIntegrated $statedir
    } else {
	debug.fx/peer {initialize orchestrated}
	# Before 2.9 we have to orchestrate `fossil export --git` with
	# base `git` commands by ourselves.
    
	set git [file join $statedir git]

	file delete -force $statedir
	file mkdir $git

	set ::env(TZ) UTC

	Run git --bare --git-dir=$git init \
	    |& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}

	if {[file exists $git/hooks/post-update.sample]} {
	    file rename -force \
		$git/hooks/post-update.sample \
		$git/hooks/post-update
	}

	fileutil::writeFile $git/description \
	    "Mirror of the $project fossil repository at $location\n"

	MarkOrchestrated $statedir
    }

    Claim $statedir $pcode

    puts [color good OK]
    debug.fx/peer {/done initialization}
    return
}

proc ::fx::peer::GitImport {statedir project location} {
    debug.fx/peer {}

    puts "Exchange [string repeat _ 40]"
    puts "Git Import $statedir"

    set git $statedir/git
    set tmp $statedir/tmp

    GitMakeReadme $git $project $location

    set current [fossil last-uuid]
    set last    [GitLastImported $git]

    puts "  Fossil @ $current"
    puts "  Git    @ $last"

    if {$last eq $current} {
	puts [color note "  No new commits"]
	puts [color good OK]
	return $current
    }

    file mkdir $tmp
    try {
	set first   [expr {$last eq {}}]
	set elapsed [GitPull $tmp $git $first ierror]

	if {$ierror} {
	    puts [color error "  Import error after $elapsed min"]
	} else {
	    puts [color note "  Imported new commits to git mirror in $elapsed min"]
	    # Remember how far we imported.
	    GitUpdateImported $git $current
	}
    } finally {
	file delete -force $tmp
    }

    puts [color good OK]
    return $current
}

proc ::fx::peer::GitMakeReadme {git project location} {
    debug.fx/peer {}
    set date [Now]

    lappend map @PROJECT $project
    lappend map @URL     $location
    lappend map @DATE    $date
    
    fileutil::writeFile $git/README.html [string map $map {
	<p>This repository is a mirror of the
	<a href="@URL">@PROJECT fossil repository</a>.
	Last updated on @DATE.</p>
    }]
    return
}

proc ::fx::peer::Now {} {
    clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S}
}

proc ::fx::peer::GitLastImported {git} {
    debug.fx/peer {}
    set idfile $git/fossil-import-id
    if {![file exists $idfile]} {
	debug.fx/peer {==> no file}
	return {}
    }
    set id [string trim [fileutil::cat $idfile]]
    debug.fx/peer {==> ($id)}
    return $id
}

proc ::fx::peer::GitUpdateImported {git current} {
    debug.fx/peer {}
    set idfile $git/fossil-import-id
    fileutil::writeFile $idfile $current
    return
}

proc ::fx::peer::GitDropLast {statedir} {
    debug.fx/peer {}
    set idfile $statedir/git/fossil-import-id
    file delete -force $idfile
    debug.fx/peer {$idfile = [file exists $idfile]}
    return
}

proc ::fx::peer::GitPull {tmp git first varerr} {
    upvar 1 $varerr ierror
    set ierror 0
    debug.fx/peer {}
    puts "  Pull"

    set begin [clock seconds]
    set src   [fossil repository-location]

    file delete -force $tmp
    file mkdir         $tmp

    set dump [file dirname $tmp]/dump

    Run git --bare  --git-dir $tmp init \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}

    Run fossil export -R $src --git > $dump.current
    GitFilter $dump.current $dump.filtered
    Run git --bare --git-dir $tmp fast-import --force \
	< $dump.filtered \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}

    # The code originally ensured that the new repository contains the
    # HEAD of the old repository. This was done under the reasoning
    # that only a bad import causes this to happen, with a corruption
    # rippling forward.
    #
    # This code is now gone. There are legitimate situations where this
    # can happen. Namely, changes to a commit message, timestamp of
    # the commit, or the user who did a commit. In fossil such changes
    # are stored in control artifacts to the side of the main history,
    # not affecting the existing hashes. Git keeps the information we
    # change in the main history and any change done fossil-side shows
    # up as a rebase. Which simply means that the change started a new
    # timeline from the point of change forward, generating a new
    # HEAD. Exactly the situation checked here for.

    file rename -force $dump.current $dump.last

    # Rename trunk to master to suit git terminology better.
    file rename $tmp/refs/heads/trunk $tmp/refs/heads/master

    # Push the new changes from tmp to local destination
    Run git --bare --git-dir $tmp remote add target $git \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}
    Run git --bare --git-dir $tmp push --force target --all \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}
    Run git --bare --git-dir $tmp push --force target --tags \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}

    file delete -force $tmp
    set elapsed [expr {([clock seconds] - $begin)/60}]

    # Also - after the very first import you need to repack the git
    # repository using 'git repack -adf --window=50' to avoid an
    # excessively large repo.  git fast-import is fast, not space
    # efficient - so always repack.

    if {$first} {
	Run git --bare  --git-dir $git repack -adf --window=50 \
	    |& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}
    }

    # Done pulling in changes
    return $elapsed
}

proc ::fx::peer::GitPush {statedir remote current mach} {
    # Perform garbage collect as required
    set git $statedir/git

    set count [Runx git --bare --git-dir $git count-objects | awk {{print $1}}]
    if {$count > 50} {
	Run git --bare --git-dir $git gc \
	    |& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}
    }

    Run git --bare --git-dir $git push --mirror $remote \
	|& sed -e "s|\\r|\\n|g" | sed -e {s|^|    |}

    # Update the local per-remote state, record the last uuid which is
    # now pushed to it.
    map remove1 fx@peer@git $remote
    map add1    fx@peer@git $remote [::list $current $mach]
    return
}

proc ::fx::peer::GitFilter {infile outfile} {
    debug.fx/peer {}

    set infile  [open $infile r]
    set outfile [open $outfile w]

    # -------------------------------------
    # Filter example for fossil export, using tcl.
    # Makes export backwards compatible to export of fossil before version 1.3.x
    # -------------------------------------
    # Wrap committer, because:
    #   - fossil since 1.3x has confused user name and email (committer / author field wrong)
    #   - fossil before 1.3x has exported a user name in email field, so thus will prevent a rebase of whole tree
    # Remove trailing newline at end of message
    # -------------------------------------
    # Copyright (c) 2015 Serg G. Brester (sebres)
    # Modified (reduced) by Andreas Kupries for fx.
    # -------------------------------------

    # Filter operation, input to output, large buffers (1000K, i.e. just shy of 1M)
    fconfigure $infile  -encoding binary -translation lf -eofchar {} -buffersize 1024000
    fconfigure $outfile -encoding binary -translation lf -eofchar {} -buffersize 1024000

    # State flags - Active when the current command is controlled by a
    # lead-in command, `commit`, or `tag`. Only one of the flags can
    # be set at any time. It is possible to have none set.
    set commit 0
    set tag    0

    # Iterate over the commands in the dump
    while 1 {
	# Get command
	set line [::gets $infile]
	if {$line == {} && [::eof $infile]} {
	    break
	}

	# Handle a data block not controlled by a tag - The block
	# contains either a commit message (when under control of a
	# commit) or a blob (any other situation)
	if {!$tag && [regexp {^data\s+(\d+)$} $line _ n]} {
	    ## Read the block, note binary!, remember blob
	    fconfigure $infile  -translation binary
	    fconfigure $outfile -translation binary
	    set data [read $infile $n]

	    # Tweak commit messages: Remove trailing whitespace, replace by single EOL.
	    if {$commit} {
		set dorg $data
		# because of conflict resp. completely different
		# messages handling between 1.2.x and 1.3.x, not
		# possible to normalize it, so just trim trailing
		# spaces, then add exact one newline, because of
		# export/import:
		if {[regsub {\s+$} $data "\n" data] ||
		    [string length $dorg] != [string length $data]} {
		    set line "data [string length $data]"
		}
		# The commit message is the last element started by a
		# commit command. Control ceases.
		set commit 0
	    }

	    ## Write the (possibly modified) data block, then go back
	    ## to regular (line) translation
	    ::puts $outfile $line
	    ::puts -nonewline $outfile $data
	    fconfigure $infile  -translation lf
	    fconfigure $outfile -translation lf

	    # Go to next command
	    continue
	}

	# Not a data block, some other command
    
	if {[regexp {^committer\s+} $line] &&
	    [regexp {^committer\s+([^<]+)\s+\<(.+)\>\s+(.*)$} $line _ usr email rest]} {
	    # recognize commit, wrap committer :
	    set commit 1; set tag 0
	    # check confused user/email :
	    if {[regexp {\S+@\S+} $usr] &&
		![regexp {\S+@\S+} $email]} {
		lassign [::list $usr $email] email usr
		set line "committer $usr <${email}> $rest"
	    }
	} elseif {!$commit} {
	    # Not in a commit section.
	    if {!$tag && [regexp {^tag\s+(.+)$} $line _ ref]} {
		# Not in a tag, and recognized a tag lead-in command, thus
		# a tag section begins.
		set tag 1
		# Rewrite to a command where the importer will accept
		# multiple refs of the same name.
		set line "reset refs/tags/$ref"
	    } elseif {$tag} {
		# In a tag section; drop tagger information, and empty
		# tag messages.
		if {[regexp {^tagger\s} $line]} {
		    # ignore "tagger <tagger>" within mode "reset_tags" ...
		    if {[incr tag] > 2} {set tag 0}
		    continue
		} elseif {[regexp {^data\s+0$} $line]} {
		    # ignore "data 0" within mode "reset_tags" ...
		    if {[incr tag] > 2} {set tag 0}
		    continue
		}
	    }
	}

	# Write the (possibly modified) command.
	::puts $outfile $line
    }

    close $infile
    close $outfile
    return
}

#-----------------------------------------------------------------------------

proc ::fx::peer::FossilVersion {} {
    debug.fx/peer {}
    set vraw [Runx fossil version]
    debug.fx/peer {v=($vraw)}
    set version {}
    set match [regexp {fossil version ([^ ]*) } $vraw -> version]
    debug.fx/peer {v=($match/$version)}
    return $version
}

proc ::fx::peer::Silent {args} {
    debug.fx/peer {}
    exec 2> /dev/null > /dev/null {*}$args
}

proc ::fx::peer::Runx {args} {
    debug.fx/peer {}
    exec 2>@ stderr {*}$args
}

proc ::fx::peer::Run {args} {
    debug.fx/peer {}
    exec 2>@ stderr >@ stdout {*}$args
}

proc ::fx::peer::Get {config} {
    debug.fx/peer {}
    # All peering information is loaded, and merged into a single
    # structure.
    #
    # dict: "fossil" + url + area -> direction
    #       "git" + url           -> last-uuid
    # TODO? git mach ?

    set map {}

    # I. Fossil peers
    dict for {url dlist} [map get fx@peer@fossil] {
	debug.fx/peer {$url ==> ($dlist)}

	foreach {area dir} $dlist {
	    debug.fx/peer {  $area ==> $dir}

	    $config @configarea set $area
	    $config @syncdir    set $dir

	    dict set map fossil $url \
		[$config @configarea] \
		[$config @syncdir]
	}
    }

    # II. Git peers.
    # Note how the configuration contains state information.
    # (Last uuid pushed to git mirror).
    dict for {url spec} [map get fx@peer@git] {
	dict set map git $url $spec
    }
    return $map
}

proc ::fx::peer::init {} {
    debug.fx/peer {}
    # Redefine to nothing for all future calls.
    proc ::fx::peer::init {} {}

    # Create mappings used to store peering information. Note how
    # their names use illegal characters. This makes them inaccessible
    # to the regular map commands, preventing users from messing
    # things up by direct editing. Of course, they still can do that
    # via direct database access and sql commands, so the commands
    # above will still validate the data they get from the repository

    # fx@peer@fossil: repo url -> dict (area dir ...)
    # fx@peer@git   : repo url -> list (last uuid sync'd so far, mach)

    foreach map {
	fx@peer@fossil
	fx@peer@git
    } {
	if {[map has $map]} continue
	map create $map
    }
    return
}

# # ## ### ##### ######## ############# ######################
## Tables to manipulate the direction pseudo-bits.
## The explicit tables are easier to maintain and understand
## than coding the implied decision table.

namespace eval ::fx::peer {
    variable dadd {
	push {
	    push push
	    pull sync
	    sync sync
	}
	pull {
	    push sync
	    pull pull
	    sync sync
	}
	sync {
	    push sync
	    pull sync
	    sync sync
	}
    }

    variable dremove {
	push {
	    push {}
	    pull push
	    sync {}
	}
	pull {
	    push pull
	    pull {}
	    sync {}
	}
	sync {
	    push pull
	    pull push
	    sync {}
	}
    }
}

# # ## ### ##### ######## ############# ######################
package provide fx::peer 0
return
