#!/usr/bin/python

import yum, os, sys

def cb():
    print "hello"

yb            = yum.YumBase()
yb.conf.cache = os.geteuid() != 0

"""
We want to search for packages that provide a perl module
These are found using perl(CPAN::Bundle) style strings.
"""

module  = sys.argv[1:]
version = sys.argv[2]

for pkg in (yb.searchPackageProvides(module)):
    required  = yum.packages.PackageEVR(pkg.epoch, version, pkg.release)
    installed = yum.packages.PackageEVR(pkg.epoch, pkg.version, pkg.release)
    order     = yum.packages.comparePoEVR(installed, required)
    if (order >= 0):
        print pkg.name, pkg.arch, pkg.version, pkg.repo

