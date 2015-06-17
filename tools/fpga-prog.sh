#!/bin/bash

rtldir=`dirname $0`/../rtl
~/scarab-ide-0.1.1/ScarabLoader/fpgaprog -v -f${rtldir}/work/hdmi_tester.bit
