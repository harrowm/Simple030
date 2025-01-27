# Run this to compile the verilog for the CPLD
# This uses the atf15xx_yosys scripts:
# > cd
# > git clone https://github.com/hoglet67/atf15xx_yosys.git
# 
# This requires wine to be installed to work on a Mac, the site above has
# instructions.
#
# Run this script on test.v using the command line:
# > ./build.sh test
# Note no .v on the filename ..

# Change the directory to point to the yosys scripts
SCRIPTDIR=/Users/malcolm/atf15xx_yosys
BASE=$1
rm $1.fit
rm $1.log
rm $1.io
rm $1.edif
rm $1.pin
rm $1.tt3
$SCRIPTDIR/run_yosys.sh $1 > $1.log
$SCRIPTDIR/run_fitter.sh -d ATF1508AS -p PLCC84 -s 15 $1 -preassign keep
# print out programmed logic
sed -n '/^PLCC84/,/^PLCC84/{/PLCC84/!p;}' $1.fit
# Program using the little atf programmer, like this ..
# > atfu program -ed $(atfu scan -n) AddressDecoder.jed
# This can be found at:
#  https://github.com/roscopeco/atfprog-tools
