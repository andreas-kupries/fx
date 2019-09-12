## -*- tcl -*-
# # ## ### ##### ######## ############# ######################

# @@ Meta Begin
# Package fx::validate::git-export-machine 0
# Meta author      {Andreas Kupries}
# Meta category    ?
# Meta description ?
# Meta location    https://core.tcl-lang.org/akupries/fx
# Meta platform    tcl
# Meta require     ?
# Meta subject     ?
# Meta summary     ?
# @@ Meta End

package require Tcl 8.5
package require cmdr::validate::common

# # ## ### ##### ######## ############# ######################

namespace eval ::fx::validate {
    namespace export git-export-machine
    namespace ensemble create
}

# # ## ### ##### ######## ############# ######################
## Custom validation type, legal enumeration of git-export-machines

namespace eval ::fx::validate::git-export-machine {
    namespace export release validate default complete legal
    namespace ensemble create

    namespace import ::cmdr::validate::common::fail
    namespace import ::cmdr::validate::common::complete-enum
}

proc ::fx::validate::git-export-machine::release  {p x} { return }
proc ::fx::validate::git-export-machine::validate {p x} {
    set cx [string tolower $x]
    if {$cx in [legal]} { return $cx }
    fail $p GIT-EXPORT-MACHINE "a git export machine" $x
}

proc ::fx::validate::git-export-machine::default  {p} { return all }
proc ::fx::validate::git-export-machine::complete {p} {
    complete-enum [legal] 1 $x
}

# # ## ### ##### ######## ############# ######################

proc ::fx::validate::git-export-machine::legal {} {
    return {integrated orchestrated}
}

# # ## ### ##### ######## ############# ######################
package provide fx::validate::git-export-machine 0
return
