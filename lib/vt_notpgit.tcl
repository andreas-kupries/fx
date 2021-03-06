## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::validate::not-peer-git 0
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
package require fx::fossil
package require cmdr::validate::common
package require fx::mgr::map
package require fx::peer

# # ## ### ##### ######## ############# ######################

namespace eval ::fx::validate {
    namespace export not-peer-git
    namespace ensemble create
}

# # ## ### ##### ######## ############# ######################
## Custom validation types: Fossil repository not-peers

namespace eval ::fx::validate::not-peer-git {
    namespace export release validate default complete
    namespace ensemble create

    namespace import ::fx::mgr::map
    namespace import ::fx::peer
    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
}

proc ::fx::validate::not-peer-git::release  {p x} { return }
proc ::fx::validate::not-peer-git::validate {p x} {
    # Force parameter, validation can happen
    # before the cmdr completion phase.
    $p config @repository-db
    peer init

    # As git peers currently only support 'push content' incremental
    # adding of areas and directions is not possible. Check that the
    # git peer is not used already, and not a fossil peer either.

    if {
	($x ni [map keys fx@peer@git]) &&
	($x ni [map keys fx@peer@fossil])
    } { return $x }
    fail $p NOT-PEER-GIT "an unused git peer" $x
}

proc ::fx::validate::not-peer-git::default  {p} { return {} }
proc ::fx::validate::not-peer-git::complete {p} { return {} }

# # ## ### ##### ######## ############# ######################
package provide fx::validate::not-peer-git 0
return
