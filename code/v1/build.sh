# Run this to compile the verilog for the CPLD
# This uses the atf15xx_yosys scripts:
# > cd
# > git clone https://github.com/hoglet67/atf15xx_yosys.git
# 
# This requires wine to be installed to work on a Mac, the site above has
# instructions.
#
# Run this script on rosco.v using the command line:
# > ./build.sh 

# Change the directory to point to the yosys scripts
SCRIPTDIR=/Users/malcolm/atf15xx_yosys
BASE=rosco
rm $BASE.fit
rm $BASE.log
rm $BASE.io
rm $BASE.edif
rm $BASE.pin
rm $BASE.tt3
$SCRIPTDIR/run_yosys.sh $BASE > $BASE.log
$SCRIPTDIR/run_fitter.sh -d ATF1508AS -p PLCC84 -s 15 $BASE -preassign keep
# print out programmed logic
sed -n '/^PLCC84/,/^PLCC84/{/PLCC84/!p;}' $BASE.fit
# Program using the little atf programmer, like this ..
# > atfu program -ed $(atfu scan -n) AddressDecoder.jed
# This can be found at:
#  https://github.com/roscopeco/atfprog-tools
