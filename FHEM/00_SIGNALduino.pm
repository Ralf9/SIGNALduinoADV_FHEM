##############################################
# $Id: 00_SIGNALduino.pm 10488 2018-11-09 18:00:00Z v3.3.2-dev $
#
# v3.3.2 (release 3.3)
# The module is inspired by the FHEMduino project and modified in serval ways for processing the incomming messages
# see http://www.fhemwiki.de/wiki/SIGNALDuino
# It was modified also to provide support for raw message handling which can be send from the SIGNALduino
# The purpos is to use it as addition to the SIGNALduino which runs on an arduno nano or arduino uno.
# It routes Messages serval Modules which are already integrated in FHEM. But there are also modules which comes with it.
# N. Butzek, S. Butzek, 2014-2015
# S.Butzek,Ralf9 2016-2018

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Data::Dumper qw(Dumper);
use Scalar::Util qw(looks_like_number);
no warnings 'portable';

#use POSIX qw( floor);  # can be removed
#use Math::Round qw();


use constant {
	SDUINO_VERSION            => "v3.3.2ralf_09.11.",
	SDUINO_INIT_WAIT_XQ       => 1.5,       # wait disable device
	SDUINO_INIT_WAIT          => 2,
	SDUINO_INIT_MAXRETRY      => 3,
	SDUINO_CMD_TIMEOUT        => 10,
	SDUINO_KEEPALIVE_TIMEOUT  => 60,
	SDUINO_KEEPALIVE_MAXRETRY => 3,
	SDUINO_WRITEQUEUE_NEXT    => 0.3,
	SDUINO_WRITEQUEUE_TIMEOUT => 2,
	
	SDUINO_DISPATCH_VERBOSE     => 5,      # default 5
	SDUINO_MC_DISPATCH_VERBOSE  => 3,      # wenn kleiner 5, z.B. 3 dann wird vor dem dispatch mit loglevel 3 die ID und rmsg ausgegeben
	SDUINO_MC_DISPATCH_LOG_ID   => '12.1', # die o.g. Ausgabe erfolgt nur wenn der Wert mit der ID uebereinstimmt
	SDUINO_PARSE_DEFAULT_LENGHT_MIN => 8,
	SDUINO_PARSE_MU_CLOCK_CHECK => 0       # wenn 1 dann ist der test ob die clock in der Toleranz ist, aktiv
};


sub SIGNALduino_Attr(@);
#sub SIGNALduino_Clear($);           # wird nicht mehr benoetigt
sub SIGNALduino_HandleWriteQueue($);
sub SIGNALduino_Parse($$$$@);
sub SIGNALduino_Read($);
#sub SIGNALduino_ReadAnswer($$$$);  # wird nicht mehr benoetigt
sub SIGNALduino_Ready($);
sub SIGNALduino_Write($$$);
sub SIGNALduino_SimpleWrite(@);
sub SIGNALduino_Log3($$$);

#my $debug=0;

my %gets = (    # Name, Data to send to the SIGNALduino, Regexp for the answer
  "version"  => ["V", 'V\s.*SIGNAL(duino|ESP).*'],
  "freeram"  => ["R", '^[0-9]+'],
  "raw"      => ["", '.*'],
  "uptime"   => ["t", '^[0-9]+' ],
  "cmds"     => ["?", '.*Use one of[ 0-9A-Za-z]+[\r\n]*$' ],
# "ITParms"  => ["ip",'.*'],
  "ping"     => ["P",'^OK$'],
  "config"   => ["CG",'^MS.*MU.*MC.*'],
  "protocolIDs"   => ["none",'none'],
  "ccconf"   => ["C0DnF", 'C0Dn11.*'],
  "ccreg"    => ["C", '^C.* = .*'],
  "ccpatable" => ["C3E", '^C3E = .*'],
#  "ITClock"  => ["ic", '\d+'],
#  "FAParms"  => ["fp", '.*' ],
#  "TCParms"  => ["dp", '.*' ],
#  "HXParms"  => ["hp", '.*' ]
);


my %sets = (
  "raw"       => '',
  "flash"     => '',
  "reset"     => 'noArg',
  "close"     => 'noArg',
  #"disablereceiver"     => "",
  #"ITClock"  => 'slider,100,20,700',
  "enableMessagetype" => 'syncedMS,unsyncedMU,manchesterMC',
  "disableMessagetype" => 'syncedMS,unsyncedMU,manchesterMC',
  "sendMsg"		=> "",
  "cc1101_freq"    => '',
  "cc1101_bWidth"  => '',
  "cc1101_rAmpl"   => '',
  "cc1101_sens"    => '',
  "cc1101_patable_433" => '-10_dBm,-5_dBm,0_dBm,5_dBm,7_dBm,10_dBm',
  "cc1101_patable_868" => '-10_dBm,-5_dBm,0_dBm,5_dBm,7_dBm,10_dBm',
);

my %patable = (
  "433" =>
  {
    "-10_dBm"  => '34',
    "-5_dBm"   => '68',
    "0_dBm"    => '60',
    "5_dBm"    => '84',
    "7_dBm"    => 'C8',
    "10_dBm"   => 'C0',
  },
  "868" =>
  {
    "-10_dBm"  => '27',
    "-5_dBm"   => '67',
    "0_dBm"    => '50',
    "5_dBm"    => '81',
    "7_dBm"    => 'CB',
    "10_dBm"   => 'C2',
  },
);


my @ampllist = (24, 27, 30, 33, 36, 38, 40, 42); # rAmpl(dB)

## Supported Clients per default
my $clientsSIGNALduino = ":IT:"
						."CUL_TCM97001:"
						."SD_RSL:"
						."OREGON:"
						."CUL_TX:"
						."SD_AS:"
						."Hideki:"
						."SD_WS07:"
						."SD_WS09:"
						." :"		# Zeilenumbruch
						."SD_WS:"
						."RFXX10REC:"
						."Dooya:"
						."SOMFY:"
						."SD_UT:"	## BELL 201.2 TXA
			        	."SD_WS_Maverick:"
			        	."FLAMINGO:"
			        	."CUL_WS:"
			        	."Revolt:"
					." :"		# Zeilenumbruch
			        	."FS10:"
			        	."CUL_FHTTK:"
			        	."Siro:"
						."FHT:"
						."FS20:"
						."CUL_EM:"
						."Fernotron:"
			      		."SIGNALduino_un:"
					; 

## default regex match List for dispatching message to logical modules, can be updated during runtime because it is referenced
my %matchListSIGNALduino = (
     "1:IT"            			=> "^i......",	  				  # Intertechno Format
     "2:CUL_TCM97001"      		=> "^s[A-Fa-f0-9]+",			  # Any hex string		beginning with s
     "3:SD_RSL"					=> "^P1#[A-Fa-f0-9]{8}",
     "5:CUL_TX"               	=> "^TX..........",         	  # Need TX to avoid FHTTK
     "6:SD_AS"       			=> "^P2#[A-Fa-f0-9]{7,8}", 		  # Arduino based Sensors, should not be default
     "4:OREGON"            		=> "^(3[8-9A-F]|[4-6][0-9A-F]|7[0-8]).*",		
     "7:Hideki"					=> "^P12#75[A-F0-9]+",
     "9:CUL_FHTTK"				=> "^T[A-F0-9]{8}",
     "10:SD_WS07"				=> "^P7#[A-Fa-f0-9]{6}F[A-Fa-f0-9]{2}(#R[A-F0-9][A-F0-9]){0,1}\$",
     "11:SD_WS09"				=> "^P9#F[A-Fa-f0-9]+",
     "12:SD_WS"					=> '^W\d+x{0,1}#.*',
     "13:RFXX10REC" 			=> '^(20|29)[A-Fa-f0-9]+',
     "14:Dooya"					=> '^P16#[A-Fa-f0-9]+',
     "15:SOMFY"					=> '^Ys[0-9A-F]+',
     "16:SD_WS_Maverick"		=> '^P47#[A-Fa-f0-9]+',
     "17:SD_UT"					=> '^P(?:14|29|30|34|46|69|81|83|86)#.*',		# universal - more devices with different protocols     "18:FLAMINGO"				=> '^P13\.?1?#[A-Fa-f0-9]+',						## Flamingo Smoke
     "18:FLAMINGO"					=> '^P13\.?1?#[A-Fa-f0-9]+',			# Flamingo Smoke
     "19:CUL_WS"				=> '^K[A-Fa-f0-9]{5,}',
     "20:Revolt"				=> '^r[A-Fa-f0-9]{22}',
     "21:FS10"					=> '^P61#[A-F0-9]+',
     "22:Siro"					=> '^P72#[A-Fa-f0-9]+',
     "23:FHT"      				=> "^81..(04|09|0d)..(0909a001|83098301|c409c401)..",
     "24:FS20"    				=> "^81..(04|0c)..0101a001", 
     "25:CUL_EM"    				=> "^E0.................", 
     "26:Fernotron"  			=> '^P82#.*',
     "27:SD_BELL"				=> '^P(?:15|32|41|57|79)#.*',
	 "X:SIGNALduino_un"			=> '^[u]\d+#.*',
);


my %ProtocolListSIGNALduino  = (
	"0"	=>	## various weather sensors
					# CUL_TCM97001 Typ - Mebus
					# MS;P0=-9298;P1=495;P2=-1980;P3=-4239;D=1012121312131313121313121312121212121212131212131312131212;CP=1;SP=0;R=223;O;m2;
					# !!! some RAWMSG are also decode under ID 68 !!!
		{
			name			=> 'weather',
			comment			=> 'Logilink, NC, WS, TCM97001 etc',
			id			=> '0',
			one			=> [1,-8],
			zero			=> [1,-4],
			sync			=> [1,-18],		
			clockabs   		=> '500',
			format     		=> 'twostate',  # not used now
			preamble		=> 's',			# prepend to converted message	 	
			postamble		=> '00',		# Append to converted message	 	
			clientmodule    => 'CUL_TCM97001',
			#modulematch     => '^s[A-Fa-f0-9]+', # not used now
			length_min      => '24',
			length_max      => '42',
			paddingbits     => '8',				 # pad up to 8 bits, default is 4
		},
	"1"	=>	## Conrad RSL
		{
			name			=> 'Conrad RSL v1',
			comment			=> 'remotes and switches',
			id			=> '1',
			one			=> [2,-1],
			zero			=> [1,-2],
			sync			=> [1,-11],		
			clockabs   		=> '560',
			format     		=> 'twostate',  		# not used now
			preamble		=> 'P1#',					# prepend to converted message	 	
			postamble		=> '',					# Append to converted message	 	
			clientmodule    => 'SD_RSL',
			modulematch     => '^P1#[A-Fa-f0-9]{8}',
			length_min 		=> '20',   # 23
			length_max 		=> '40',   # 24
        },
    "2"    => 
        {
			name			=> 'AS, Self build arduino sensor',
			comment         => 'developModule. SD_AS module is only in github available',
			developId 		=> 'm',
			id          	=> '2',
			one				=> [1,-2],
			zero			=> [1,-1],
			sync			=> [1,-20],
			clockabs     	=> '500',
			format 			=> 'twostate',	
			preamble		=> 'P2#',		# prepend to converted message		
			clientmodule    => 'SD_AS',
			modulematch     => '^P2#.{7,8}',
			length_min      => '32',
			length_max      => '34',
			paddingbits     => '8',		    # pad up to 8 bits, default is 4
        },
	"3"	=>	## itv1 - remote like WOFI Lamp | Intertek Modell 1946518 // ELRO
					# need more Device Infos / User Message
		{
			name			=> 'itv1',
			comment			=> 'remote for WOFI | Intertek',
			id			=> '3',
			one			=> [3,-1],
			zero			=> [1,-3],
			#float			=> [-1,3],		# not full supported now later use
			sync			=> [1,-31],
			clockabs     	=> -1,	# -1=auto	
			format 			=> 'twostate',	# not used now
			preamble		=> 'i',			
			clientmodule    => 'IT',
			modulematch     => '^i......',
			length_min      => '24',
			length_max      => '24'
			},
    "3.1"    => # MS;P0=-11440;P1=-1121;P2=-416;P5=309;P6=1017;D=150516251515162516251625162516251515151516251625151;CP=5;SP=0;R=66;
			    # MS;P1=309;P2=-1130;P3=1011;P4=-429;P5=-11466;D=15123412121234123412141214121412141212123412341234;CP=1;SP=5;R=38;  Gruppentaste, siehe Kommentar in sub SIGNALduino_bit2itv1
			    # need more Device Infos / User Message
		{
			name			=> 'itv1_sync40',
			comment			=> 'IT remote control PAR 1000, ITS-150, AB440R',
			id			=> '3',
			one			=> [3.5,-1],
			zero			=> [1,-3.8],
			float			=> [1,-1],	# fuer Gruppentaste (nur bei ITS-150,ITR-3500 und ITR-300), siehe Kommentar in sub SIGNALduino_bit2itv1
			sync			=> [1,-44],
			clockabs     	=> -1,	# -1=auto	
			format 			=> 'twostate',	# not used now
			preamble		=> 'i',			
			clientmodule    => 'IT',
			modulematch     => '^i......',
			length_min      => '24',
			length_max      => '24',
			postDemodulation => \&SIGNALduino_bit2itv1,
			},
    "4"    => # need more Device Infos / User Message
        {
			name			=> 'arctech2',	
			id			=> '4',
			#one			=> [1,-5,1,-1],  
			#zero			=> [1,-1,1,-5],  
			one				=> [1,-5],  
			zero			=> [1,-1],  
			#float			=> [-1,3],		# not full supported now, for later use
			sync			=> [1,-14],
			clockabs     	=> -1,			# -1 = auto
			format 			=> 'twostate',	# tristate can't be migrated from bin into hex!
			preamble		=> 'i',			# Append to converted message	
			postamble		=> '00',		# Append to converted message	 	
			clientmodule    => 'IT',
			modulematch     => '^i......',
			length_min      => '32',
			length_max			=> '44',		# Don't know maximal lenth of a valid message
		},
    "5"    => 	# Unitec, Modellnummer 6899/45108
				# https://github.com/RFD-FHEM/RFFHEM/pull/389#discussion_r237232347 | https://github.com/RFD-FHEM/RFFHEM/pull/389#discussion_r237245943
				# MU;P0=-31960;P1=660;P2=401;P3=-1749;P5=276;D=232353232323232323232323232353535353232323535353535353535353535010;CP=5;R=38;
				# MU;P0=-1757;P1=124;P2=218;P3=282;P5=-31972;P6=644;P7=-9624;D=010201020303030202030303020303030202020202020203030303035670;CP=2;R=32;
				# MU;P0=-1850;P1=172;P3=-136;P5=468;P6=236;D=010101010101310506010101010101010101010101010101010101010;CP=1;R=30;
				# A AN:
				# MU;P0=132;P1=-4680;P2=508;P3=-1775;P4=287;P6=192;D=123434343434343634343436363434343636343434363634343036363434343;CP=4;R=2;
				# A AUS:
				# MU;P0=-1692;P1=132;P2=194;P4=355;P5=474;P7=-31892;D=010202040505050505050404040404040404040470;CP=4;R=27; 
		{
			name				=> 'Unitec',
			comment				=> 'remote control model 6899/45108',
			id				=> '5',
			one				=> [3,-1], # ?
			zero			=> [1,-3], # ?
			clockabs     	=> 500,    # ?
			developId       => 'y',
			format 			=> 'twostate',
			preamble		=> 'u5',
			#clientmodule    => '',
			#modulematch     => '',
			length_min      => '24',   # ?
			length_max      => '24',   # ?
		},   
	"6"	=>	## Eurochron Protocol
		{
			name			=> 'weather',
			comment			=> 'unknown sensor is under development',
			id			=> '6',
			one			=> [1,-10],
			zero			=> [1,-5],
			sync			=> [1,-36],		# This special device has no sync
			clockabs     	=> 220,			# -1 = auto
			format 			=> 'twostate',	# tristate can't be migrated from bin into hex!
			preamble		=> 'u6#',			# Append to converted message	
			#clientmodule    => '',   	# not used now
			#modulematch     => '^u......',  # not used now
			length_min      => '24',
		},
	"7"    => ## weather sensors like EAS800z
			  # MS;P1=-3882;P2=504;P3=-957;P4=-1949;D=21232424232323242423232323232323232424232323242423242424242323232324232424;CP=2;SP=1;R=249;m=2;
        {
			name			=> 'weatherID7',	
			comment			=> 'EAS800z, FreeTec NC-7344, HAMA TS34A',
			id          		=> '7',
			one			=> [1,-4],
			zero			=> [1,-2],
			sync			=> [1,-8],		 
			clockabs     	=> 484,			
			format 			=> 'twostate',	
			preamble		=> 'P7#',		# prepend to converted message	
			clientmodule    => 'SD_WS07',
			modulematch     => '^P7#.{6}F.{2}$',
			length_min      => '35',
			length_max      => '40',
		}, 
	"8"    =>   ## TX3 (ITTX) Protocol
				# MU;P0=-1046;P1=1339;P2=524;P3=-28696;D=010201010101010202010101010202010202020102010101020101010202020102010101010202310101010201020101010101020201010101020201020202010201010102010101020202010201010101020;CP=2;R=4;
        {
			name		=> 'TX3 Protocol',	
			id          	=> '8',
			one			=> [1,-2],
			zero			=> [2,-2],
			#start			=> [2,-55],
			clockabs     	=> 470,
			clockpos	=> ['one',0],
			format 			=> 'pwm',
			preamble		=> 'TX',		# prepend to converted message	
			clientmodule    => 'CUL_TX',
			modulematch     => '^TX......',
			length_min      => '43',
			length_max      => '44',
			remove_zero     => 1,           # Removes leading zeros from output
		}, 	
	"9"    => 			## Funk Wetterstation CTW600
		{
			name		=> 'CTW 600',	
			comment		=> 'FunkWS WH1080/WH3080/CTW600',
			id          	=> '9',
			zero			=> [3,-2],
			one				=> [1,-2],
			#float			=> [-1,3],		# not full supported now, for later use
			#sync			=> [1,-8],		# 
			clockabs     	=> 480,			# -1 = auto undef=noclock
			clockpos	=> ['one',0],
			format 			=> 'pwm',	    # tristate can't be migrated from bin into hex!
			preamble		=> 'P9#',		# prepend to converted message	
			clientmodule    => 'SD_WS09',
			#modulematch     => '^u9#.....',  # not used now
			length_min      => '60',
			length_max      => '120',
		}, 	
	"10"	=>	## Oregon Scientific 2
		{
			name		=> 'Oregon Scientific v2|v3',
			comment		=> 'temperature / humidity or other sensors',
			id          	=> '10',
			clockrange     	=> [300,520],			# min , max
			format 			=> 'manchester',	    # tristate can't be migrated from bin into hex!
			clientmodule    => 'OREGON',
			modulematch     => '^(3[8-9A-F]|[4-6][0-9A-F]|7[0-8]).*',
			length_min      => '64',
			length_max      => '220',
			method          => \&SIGNALduino_OSV2, # Call to process this message
			polarity        => 'invert',			
		}, 	
	"11"	=>	## Arduino Sensor
		{
			name		=> 'Arduino',
			comment		=> 'for Arduino based sensors',	
			id          	=> '11',
			clockrange     	=> [380,425],			# min , max
			format 			=> 'manchester',	    # tristate can't be migrated from bin into hex!
			preamble		=> 'P2#',		# prepend to converted message	
			clientmodule    => 'SD_AS',
			modulematch     => '^P2#.{7,8}',
			length_min      => '52',
			length_max      => '56',
			method          => \&SIGNALduino_AS # Call to process this message
		}, 
	"12"	=>	## Hideki
				# MC;LL=-1040;LH=904;SL=-542;SH=426;D=A8C233B53A3E0A0783;C=485;L=72;R=213;
		{
			name		=> 'Hideki',
			comment		=> 'temperature / humidity or other sensors',
			id          	=> '12',
			clockrange     	=> [420,510],                   # min, max better for Bresser Sensors, OK for hideki/Hideki/TFA too     
			format 			=> 'manchester',	
			preamble		=> 'P12#',						# prepend to converted message	
			clientmodule    => 'hideki',   				# not used now
			modulematch     => '^P12#75.+',  						# not used now
			length_min      => '71',
			length_max      => '128',
			method          => \&SIGNALduino_Hideki,	# Call to process this message
			polarity        => 'invert',			
		}, 	
	"12.1"    => 			## hideki
		{
            name			=> 'Hideki protocol not invert',
			comment		=> 'only for test of the firmware dev-r33_fixmc',
			id          	=> '12',
			clockrange     	=> [420,510],                   # min, max better for Bresser Sensors, OK for hideki/Hideki/TFA too     
			format 			=> 'manchester',	
			preamble		=> 'P12#',						# prepend to converted message	
			clientmodule    => 'hideki',   				# not used now
			modulematch     => '^P12#75.+',  						# not used now
			length_min      => '71',
			length_max      => '128',
			method          => \&SIGNALduino_Hideki,	# Call to process this message
			#polarity        => 'invert',			
		}, 	
	"13"	=>	## FLAMINGO FA21
						# https://github.com/RFD-FHEM/RFFHEM/issues/21
						# https://github.com/RFD-FHEM/RFFHEM/issues/233
						# MS;P0=-1413;P1=757;P2=-2779;P3=-16079;P4=8093;P5=-954;D=1345121210101212101210101012121012121210121210101010;CP=1;SP=3;R=33;O;
		{
			name						=> 'FLAMINGO FA21',
			comment					=> 'FLAMINGO FA21 smoke detector (message decode as MS)',
			id							=> '13',
			one							=> [1,-2],
			zero						=> [1,-4],
			sync						=> [1,-20,10,-1],
			clockabs				=> 800,
			format					=> 'twostate',
			preamble				=> 'P13#',				# prepend to converted message
			clientmodule		=> 'FLAMINGO',
			#modulematch		=> 'P13#.*',
			length_min			=> '24',
			length_max			=> '26',
		},		
	"13.1"  =>	## FLAMINGO FA20RF
				# MU;P0=-1384;P1=815;P2=-2725;P3=-20001;P4=8159;P5=-891;D=01010121212121010101210101345101210101210101212101010101012121212101010121010134510121010121010121210101010101212121210101012101013451012101012101012121010101010121212121010101210101345101210101210101212101010101012121212101010121010134510121010121010121;CP=1;O;
				# MU;P0=-17201;P1=112;P2=-1419;P3=-28056;P4=8092;P5=-942;P6=777;P7=-2755;D=12134567676762626762626762626767676762626762626267626260456767676262676262676262676767676262676262626762626045676767626267626267626267676767626267626262676262604567676762626762626762626767676762626762626267626260456767676262676262676262676767676262676262;CP=6;O;
				## FLAMINGO FA22RF (only MU Message)
				# MU;P0=-5684;P1=8149;P2=-887;P3=798;P4=-1393;P5=-2746;P6=-19956;D=0123434353534353434343434343435343534343534353534353612343435353435343434343434343534353434353435353435361234343535343534343434343434353435343435343535343536123434353534353434343434343435343534343534353534353612343435353435343434343434343534353434353435;CP=3;R=0;
				# Times measured
				# Sync 8100 microSec, 900 microSec | Bit1 2700 microSec low - 800 microSec high | Bit0 1400 microSec low - 800 microSec high | Pause Repeat 20000 microSec | 1 Sync + 24Bit, Totaltime 65550 microSec without Sync
		{
			name			=> 'FLAMINGO FA22RF / FA21RF / LM-101LD',
			comment			=> 'FLAMINGO | Unitec smoke detector (message decode as MU)',
			id			=> '13.1',
			one			=> [1,-1.8],
			zero			=> [1,-3.5],
			start			=> [-23.5,10,-1],
			clockabs		=> 800,
			clockpos	=> ['cp'],
			format 			=> 'twostate',	  		
			preamble		=> 'P13.1#',				# prepend to converted message
			clientmodule    => 'FLAMINGO',   				# not used now
			#modulematch     => 'P13#.*',  				# not used now
			length_min      => '24',
			length_max      => '24',
		}, 		
	"13.2"	=>	## LM-101LD Rauchm
					# MS;P1=-2708;P2=796;P3=-1387;P4=-8477;P5=8136;P6=-904;D=2456212321212323232321212121212121212123212321212121;CP=2;SP=4;
		{
			name		=> 'LM-101LD',
			comment		=> 'Unitec smoke detector (message decode as MS)',
			id		=> '13',
			zero		=> [1,-1.8],
			one		=> [1,-3.5],
			sync		=> [1,-11,10,-1.2],
			clockabs     	=> 790,
			format 		=> 'twostate',	    # 
			preamble	=> 'P13#',	# prepend to converted message	
			clientmodule    => 'FLAMINGO',
			#modulematch     => '', # not used now
			length_min      => '24',
			length_max      => '24',
		},
	"14"	=>	## LED X-MAS Chilitec model 22640
						# https://github.com/RFD-FHEM/RFFHEM/issues/421 | https://forum.fhem.de/index.php/topic,94211.msg869214.html#msg869214
						# MS;P0=988;P1=-384;P2=346;P3=-1026;P4=-4923;D=240123012301230123012323232323232301232323;CP=2;SP=4;R=0;O;m=1;
						# MS;P0=-398;P1=974;P3=338;P4=-1034;P6=-4939;D=361034103410341034103434343434343410103434;CP=3;SP=6;R=0;
		{
			name				=> 'LED X-MAS',
			comment				=> 'Chilitec model 22640',
			id				=> '14',
			one				=> [3,-1],
			zero				=> [1,-3],
			sync					=> [1,-14],
			clockabs				=> 350,
			format					=> 'twostate',
			preamble				=> 'P14#',				# prepend to converted message
			clientmodule		=> 'SD_UT',
			#modulematch			=> '^P14#.*',
			length_min			=> '20',
			length_max			=> '20',
		}, 			
	"15"    => 			## TCM234759
		{
			name			=> 'TCM 234759 Bell',	
			comment         => 'wireless doorbell TCM 234759 Tchibo',
			id          	=> '15',
			one				=> [1,-1],
			zero			=> [1,-2],
			sync			=> [1,-45],
			clockabs		=> 700,
			format					=> 'twostate',
			preamble				=> 'P15#',				# prepend to converted message
			clientmodule		=> 'SD_BELL',
			modulematch			=> '^P15#.*',
			length_min      => '10',
			length_max      => '20',
		}, 	
	"16" => # Rohrmotor24 und andere Funk Rolladen / Markisen Motoren
			# ! same definition how ID 72 !
			# https://forum.fhem.de/index.php/topic,49523.0.html							   
            # MU;P0=-1608;P1=-785;P2=288;P3=650;P4=-419;P5=4676;D=1212121213434212134213434212121343434212121213421213434212134345021213434213434342121212121343421213421343421212134343421212121342121343421213432;CP=2;
			# MU;P0=-1562;P1=-411;P2=297;P3=-773;P4=668;P5=4754;D=1232341234141234141234141414123414123232341232341412323414150234123234123232323232323234123414123414123414141412341412323234123234141232341415023412323412323232323232323412341412341412341414141234141232323412323414123234142;CP=2;
		{
			name			=> 'Dooya',
			comment			=> 'Rohrmotor24 and other radio shutters / awnings motors',
			id			=> '16',
			one			=> [2,-1],
			zero			=> [1,-3],
			start           => [17,-5],
			clockabs		=> 280,
			clockpos	=> ['zero',0],
			format 			=> 'twostate',	  		
			preamble		=> 'P16#',				# prepend to converted message	
			clientmodule    => 'Dooya',
			#modulematch     => '',  				# not used now
			length_min      => '39',
			length_max      => '40',
		}, 	
    "17"    => 
        {
			name			=> 'arctech / intertechno',
			id          	=> '17',
			one				=> [1,-5,1,-1],  
			zero			=> [1,-1,1,-5],  
			#one			=> [1,-5],  
			#zero			=> [1,-1],  
			sync			=> [1,-10],
			float			=> [1,-1,1,-1],
			end			=> [1,-40],
			clockabs     	=> -1,			# -1 = auto
			format 			=> 'twostate',	# tristate can't be migrated from bin into hex!
			preamble		=> 'i',			# Append to converted message	
			postamble		=> '00',		# Append to converted message	 	
			clientmodule    => 'IT',
			modulematch     => '^i......',
			length_min      => '32',
			length_max      => '34',
			postDemodulation => \&SIGNALduino_bit2Arctec,
		},
	 "17.1"	=> # intertechno --> MU anstatt sonst MS (ID 17)
			# MU;P0=344;P1=-1230;P2=-200;D=01020201020101020102020102010102010201020102010201020201020102010201020101020102020102010201020102010201010200;CP=0;R=0;
			# MU;P0=346;P1=-1227;P2=-190;P4=-10224;P5=-2580;D=0102010102020101020201020101020102020102010102010201020102010201020201020102010201020101020102020102010102020102010201020104050201020102010102020101020201020101020102020102010102010201020102010201020201020102010201020101020102020102010102020102010201020;CP=0;R=0;
			# MU;P0=351;P1=-1220;P2=-185;D=01 0201 0102 020101020201020101020102020102010102010201020102010201020201020102010201020101020102020102010201020102010201020100;CP=0;R=0;
			# MU;P0=355;P1=-189;P2=-1222;P3=-10252;P4=-2604;D=01020201010201020201020101020102020102010201020102010201010201020102010201020201020101020102010201020102010201020 304 0102 01020102020101020201010201020201020101020102020102010201020102010201010201020102010201020201020101020102010201020102010201020 304 01020;CP=0;R=0;
			# https://www.sweetpi.de/blog/329/ein-ueberblick-ueber-433mhz-funksteckdosen-und-deren-protokolle
        {
			name			=> 'intertechno',
			comment 		=> 'PIR-1000 | ITT-1500',
			id          	=> '17.1',
 			one			=> [1,-5,1,-1],
 			zero			=> [1,-1,1,-5],
 			start			=> [1,-44,1,-11],
			clockabs    	=> 230,			# -1 = auto
			clockpos	=> ['cp'],
			format 			=> 'twostate',	# tristate can't be migrated from bin into hex!
			preamble		=> 'i',			# Append to converted message	
			postamble		=> '00',		# Append to converted message	 	
			clientmodule    => 'IT',
			modulematch     => '^i......',
 			length_min      => '28',
			length_max     	=> '34',
			postDemodulation => \&SIGNALduino_bit2Arctec,
		},
	"18"	=>	## Oregon Scientific v1
						# MC;LL=-2721;LH=3139;SL=-1246;SH=1677;D=1A51FF47;C=1463;L=32;R=12;
		{
			name		=> 'Oregon Scientific v1',
			comment		=> 'temperature / humidity or other sensors',
			id          	=> '18',
			clockrange     	=> [1400,1500],			# min , max
			format 			=> 'manchester',	    # tristate can't be migrated from bin into hex!
			preamble		=> '',					
			clientmodule    => 'OREGON',
			modulematch     => '^[0-9A-F].*',
			length_min      => '31',
			length_max      => '32',
			polarity        => 'invert',		    # invert bits
			method          => \&SIGNALduino_OSV1   # Call to process this message
		},
	"19" => # minify Funksteckdose
            # https://github.com/RFD-FHEM/RFFHEM/issues/114
			# MU;P0=293;P1=-887;P2=-312;P6=-1900;P7=872;D=6727272010101720172720101720172010172727272720;CP=0;
			# MU;P0=9078;P1=-308;P2=180;P3=-835;P4=881;P5=309;P6=-1316;D=0123414141535353415341415353415341535341414141415603;CP=5;
		{
			name			=> 'minify',
			comment			=> 'remote control RC202',
			id			=> '19',
			one			=> [3,-1],
			zero			=> [1,-3],
			clockabs		=> 300,
			format 			=> 'twostate',	  		
			preamble		=> 'u19#',				# prepend to converted message
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '19',
			length_max      => '23',				# not confirmed, length one more as MU Message
		},
	"20" => # Livolo         	
            # https://github.com/RFD-FHEM/RFFHEM/issues/29
         	# MU;P0=-195;P1=151;P2=475;P3=-333;D=010101010102010101010101013101013101010101013101010201010101010101010101010101010101010101020101010101010101010101010101010101010102010101010101013101013101;CP=1;
			#
			# protocol sends 24 to 47 pulses per message.
			# First pulse is the header and is 595 μs long. All subsequent pulses are either 170 μs (short pulse) or 340 μs (long pulse) long.
			# Two subsequent short pulses correspond to bit 0, one long pulse corresponds to bit 1. There is no footer. The message is repeated for about 1 second.
			#             _____________                 ___                 _______
			# Start bit: |             |___|    bit 0: |   |___|    bit 1: |       |___|								   
		{
			name			=> 'Livolo',
			comment			=> 'remote control / dimmmer / switch ...',
			id			=> '20',
			one			=> [3],
			zero			=> [1],
			start			=> [5],				
			clockabs		=> 110,                  #can be 90-140
			clockpos		=> ['zero',0],
			format 			=> 'twostate',	  		
			preamble		=> 'u20#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '16',
			filterfunc      => 'SIGNALduino_filterSign',
		},
	"21"	=>	## Einhell Garagentor
						# https://forum.fhem.de/index.php?topic=42373.0 | user have no RAWMSG
						# static adress: Bit 1-28 | channel remote Bit 29-32 | repeats 31 | pause 20 ms
						# Channelvalues dez
						# 1 left 1x kurz | 2 left 2x kurz | 3 left 3x kurz | 5 right 1x kurz | 6 right 2x kurz | 7 right 3x kurz ... gedrückt
		{
			name		=> 'Einhell Garagedoor',
			comment         => 'remote ISC HS 434/6',
			id          	=> '21',
			one				=> [-3,1],
			zero			=> [-1,3],
			#sync			=> [-50,1],	
			start  			=> [-50,1],	
			clockabs		=> 400,                  #ca 400us
			clockpos	=> ['one',1],
			format 			=> 'twostate',	  		
			preamble		=> 'u21#',				# prepend to converted message	
			#clientmodule   => '',   				# not used now
			#modulematch    => '',  				# not used now
			length_min      => '32',
			length_max      => '32',				
			paddingbits     => '1',					# This will disable padding 
		},
	"22" => ## HAMULiGHT LED Trafo
					# https://forum.fhem.de/index.php?topic=89301.0
					# MU;P0=-589;P1=209;P2=-336;P3=32001;P4=-204;P5=1194;P6=-1200;P7=602;D=0123414145610747474101010101074741010747410741074101010101074741010741074741414141456107474741010101010747410107474107410741010101010747410107410747414141414561074747410101010107474101074741074107410101010107474101074107474141414145610747474101010101074;CP=1;R=25;
					# MU;P0=204;P1=-596;P2=598;P3=-206;P4=1199;P5=-1197;D=0123230123012301010101012323010123012323030303034501232323010101010123230101232301230123010101010123230101230123230303030345012323230101010101232301012323012301230101010101232301012301232303030303450123232301010101012323010123230123012301010101012323010;CP=0;R=25;
		{
			name						=> 'HAMULiGHT',
			comment					=> 'remote control for LED Transformator',
			id							=> '22',
			one							=> [1,-3],
			zero						=> [3,-1],
			start						=> [6,-6],
			clockabs				=> 200,						# ca 200us
			format					=> 'twostate',
			preamble				=> 'u22#',				# prepend to converted message
			#clientmodule    => '',
			#modulematch     => '',
			length_min      => '32',
			length_max      => '32',
		},
	"23"	=>	## Pearl Sensor
		{
			name			=> 'Pearl',
			comment			=> 'unknown sensortyp',	
			id			=> '23',
			one			=> [1,-6],
			zero			=> [1,-1],
			sync			=> [1,-50],				
			clockabs		=> 200,                  #ca 200us
			format 			=> 'twostate',	  		
			preamble		=> 'u23#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '36',
			length_max      => '44',				
		},
	"24" => # visivon
	        # https://github.com/RFD-FHEM/RFFHEM/issues/39
			# MU;P0=132;P1=500;P2=-233;P3=-598;P4=-980;P5=4526;D=012120303030303120303030453120303121212121203121212121203121212121212030303030312030312031203030303030312031203031212120303030303120303030453120303121212121203121212121203121212121212030303030312030312031203030303030312031203031212120303030;CP=0;O;
		{
			name			=> 'visivon remote',	
			id			=> '24',
			one			=> [3,-2],
			zero			=> [1,-5],
			#one			=> [3,-2],
			#zero			=> [1,-1],
			start           => [30,-5],
			clockabs		=> 150,                  #ca 150us
			clockpos	=> ['zero',0],
			format 			=> 'twostate',	  		
			preamble		=> 'u24#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '54',
			length_max      => '58',				
		},
	"25" => # LES remote for led lamp
            # https://github.com/RFD-FHEM/RFFHEM/issues/40
	        # MS;P0=-376;P1=697;P2=-726;P3=322;P4=-13188;P5=-15982;D=3530123010101230123230123010101010101232301230123234301230101012301232301230101010101012323012301232;CP=3;SP=5;O;
		{
			name		=> 'les led remote',	
			id          	=> '25',
			one				=> [-2,1],
			zero			=> [-1,2],
			sync			=> [-46,1],				# this is a end marker, but we use this as a start marker
			clockabs		=> 350,                 #ca 350us
			format 			=> 'twostate',	  		
			preamble		=> 'u25#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '24',
			length_max      => '50',				# message has only 24 bit, but we get more than one message, calculation has to be corrected
		},
	"26"	=>	## some remote code send by flamingo style remote controls
						# https://forum.fhem.de/index.php/topic,43292.msg352982.html#msg352982
						# MU;P0=1086;P1=-433;P2=327;P3=-1194;P4=-2318;P5=2988;D=01012323010123010101230123012323232323010101232324010123230101230101012301230123232323230101012323240101232301012301010123012301232323232301010123232401012323010123010101230123012323232323010101232353;CP=2;
		{
			name		=> 'remote26',	
			id          	=> '26',
			one				=> [1,-3],
			zero			=> [3,-1],
#			sync			=> [1,-6],				# Message is not provided as MS, due to small fact
			start 			=> [1,-6],				# Message is not provided as MS, due to small fact
			clockabs		=> 380,                 #ca 380
			clockpos		=> ['one',0],
			format 			=> 'twostate',	  		
			preamble		=> 'u26#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '24',
			length_max      => '24',				# message has only 24 bit, but we get more than one message, calculation has to be corrected
		},
	"27"	=>	## some remote code, send by flamingo style remote controls
						# https://forum.fhem.de/index.php/topic,43292.msg352982.html#msg352982
						# MU;P0=963;P1=-559;P2=393;P3=-1134;P4=2990;P5=-7172;D=01012323010123010101230123012323232323010101232345010123230101230101012301230123232323230101012323450101232301012301010123012301232323232301010123234501012323010123010101230123012323232323010101232323;CP=2;
		{
			name		=> 'remote27',	
			id          	=> '27',
			one				=> [1,-2],
			zero			=> [2,-1],
			start			=> [6,-15],				# Message is not provided as MS, worakround is start
			clockabs		=> 480,                 #ca 480
			clockpos	=> ['one',0],
			format 			=> 'twostate',	  		
			preamble		=> 'u27#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '24',
			length_max      => '24',				
		},
	"28" => # some remote code, send by aldi IC Ledspots
		{
			name			=> 'IC Ledspot',	
			id          	=> '28',
			one				=> [1,-1],
			zero			=> [1,-2],
			start			=> [4,-5],				
			clockabs		=> 600,                 #ca 600
			clockpos	=> ['cp'],
			format 			=> 'twostate',	  		
			preamble		=> 'u28#',				# prepend to converted message
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '8',
			length_max      => '8',				
		},
	"29" => # example remote control with HT12E chip
           # MU;P0=250;P1=-492;P2=166;P3=-255;P4=491;P5=-8588;D=052121212121234121212121234521212121212341212121212345212121212123412121212123452121212121234121212121234;CP=0;
           # https://forum.fhem.de/index.php/topic,58397.960.html
		{
			name		=> 'HT12e remote',	
			comment         => 'Remote control for example Westinghouse airfan with five Buttons (developModule SD_UT is only in github available)',
			id          	=> '29',
			one				=> [-2,1],
			zero			=> [-1,2],
			start           => [-35,1],         # Message is not provided as MS, worakround is start
			clockabs        => 235,             # ca 220
			clockpos	=> ['one',1],
			format          => 'twostate',      # there is a pause puls between words
			preamble        => 'P29#',				# prepend to converted message	
			clientmodule    => 'SD_UT', 
			modulematch     => '^P29#.{3}',
			length_min      => '12',
			length_max      => '12',
		},
	"30" => # a unitec remote door reed switch
			# https://forum.fhem.de/index.php?topic=43346.0
			# MU;P0=-10026;P1=-924;P2=309;P3=-688;P4=-361;P5=637;D=123245453245324532453245320232454532453245324532453202324545324532453245324532023245453245324532453245320232454532453245324532453202324545324532453245324532023245453245324532453245320232454532453245324532453202324545324532453245324532023240;CP=2;O;
			# MU;P0=307;P1=-10027;P2=-691;P3=-365;P4=635;D=0102034342034203420342034201020343420342034203420342010203434203420342034203420102034342034203420342034201020343420342034203420342010203434203420342034203420102034342034203420342034201;CP=0;
		{
			name			=> 'unitec47031',	
			comment         => 'unitec remote door reed switch 47031 (developModule SD_UT module is only in github available)',
			id          	=> '30',
			one			=> [-2,1],
			zero			=> [-1,2],
			start			=> [-30,1],				# Message is not provided as MS, worakround is start
			clockabs		=> 330,                 # ca 300 us
			clockpos		=> ['one',1],
			format 			=> 'twostate',	  		# there is a pause puls between words
			preamble		=> 'P30#',				# prepend to converted message	
			clientmodule    => 'SD_UT', 
			modulematch     => '^P30#.{3}',
			length_min      => '12',
			length_max      => '12',				# message has only 10 bit but is paddet to 12
		},
	"31"	=>	## Pollin ISOTRONIC - 12 Tasten remote
						# remote basicadresse with 12bit -> changed if push reset behind battery cover
						# https://github.com/RFD-FHEM/RFFHEM/issues/44
						# MU;P0=-9584;P1=592;P2=-665;P3=1223;P4=-1311;D=01234141412341412341414123232323412323234;CP=1;R=0;
						# MU;P0=-12724;P1=597;P2=-667;P3=1253;P4=-1331;D=01234141412341412341414123232323232323232;CP=1;R=0;
						# MU;P0=-9588;P1=600;P2=-664;P3=1254;P4=-1325;D=01234141412341412341414123232323232323232;CP=1;R=0;
		{
			name			=> 'Pollin ISOTRONIC',
			comment			=> 'remote control model 58608 with 12 buttons',
			id			=> '31',
			one			=> [-1,2],
			zero			=> [-2,1],
			start			=> => [-18,1],
			clockabs		=> 600,
			clockpos		=> ['zero',1],
			format 			=> 'twostate',	  		
			preamble		=> 'u31#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '19',
			length_max      => '20',				
		},
	"32" => #FreeTec PE-6946 -> http://www.free-tec.de/Funkklingel-mit-Voic-PE-6946-919.shtml
			# https://github.com/RFD-FHEM/RFFHEM/issues/49
			# MS;P0=-266;P1=160;P3=-690;P4=580;P5=-6628;D=15131313401340134013401313404040404040404040404040;CP=1;SP=5;O;
    	{   
			name			=> 'freetec 6946',
			comment			=> 'Doorbell FreeTec PE-6946',
			id			=> '32',
			one			=> [4,-2],
			zero			=> [1,-4],
			sync			=> [1,-43],				
			clockabs		=> 150,                 #ca 150us
			format 			=> 'twostate',	  		
			preamble		=> 'u32#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '24',
			length_max      => '24',				
    	},
	"32.1" => #FreeTec PE-6946 -> http://www.free-tec.de/Funkklingel-mit-Voic-PE-6946-919.shtml
			# https://github.com/RFD-FHEM/RFFHEM/issues/315
			# MU;P0=-6676;P1=578;P2=-278;P4=-680;P5=176;P6=-184;D=541654165412545412121212121212121212121250545454125412541254125454121212121212121212121212;CP=1;R=0;
			# MU;P0=146;P1=245;P3=571;P4=-708;P5=-284;P7=-6689;D=14351435143514143535353535353535353535350704040435043504350435040435353535353535353535353507040404350435043504350404353535353535353535353535070404043504350435043504043535353535353535353535350704040435043504350435040435353535353535353535353507040404350435;CP=3;R=0;O;
			# MU;P0=-6680;P1=162;P2=-298;P4=253;P5=-699;P6=555;D=45624562456245456262626262626262626262621015151562156215621562151562626262626262626262626210151515621562156215621515626262626262626262626262;CP=6;R=0;
    	{   
			name			=> 'freetec 6946',	
			comment         => 'Doorbell FreeTec PE-6946',
			id          	=> '32',
			one				=> [4,-2],
			zero			=> [1,-5],
			start           => [1,-46],
			clockabs		=> 150,
			clockpos		=> ['zero',0],
			format 			=> 'twostate',	  		
			preamble		=> 'u32#',				# prepend to converted message	
			#clientmodule    => '',   				# not used now
			#modulematch     => '',  				# not used now
			length_min      => '24',
			length_max      => '24',				
    	},
	"33"	=>	## Thermo-/Hygrosensor S014, renkforce E0001PA, Conrad S522, TX-EZ6 (Weatherstation TZS First Austria)
						# https://forum.fhem.de/index.php?topic=35844.0
						# MS;P0=-7871;P2=-1960;P3=578;P4=-3954;D=030323232323434343434323232323234343434323234343234343234343232323432323232323232343234;CP=3;SP=0;R=0;m=0;
						# sensor id=62, channel=1, temp=21.1, hum=76, bat=ok
						# !! ToDo Tx-EZ6 neues Attribut ins Modul bauen um Trend + CRC auszuwerten !!
		{
			name			=> 'weather33',		
			comment			=> 'S014, TFA 30.3200, TCM, Conrad S522, renkforce E0001PA, TX-EZ6',
			id			=> '33',
			one			=> [1,-8],
			zero			=> [1,-4],
			sync			=> [1,-16],
			clockabs   		=> '500',
			format     		=> 'twostate',  		# not used now
			preamble		=> 'W33#',				# prepend to converted message	
			postamble		=> '',					# Append to converted message	 	
			clientmodule    => 'SD_WS',
			#modulematch     => '',     			# not used now
			length_min      => '42',
			length_max      => '44',
    	},
    "34" => # QUIGG GT-7000 Funk-Steckdosendimmer | transmitter DMV-7000 - receiver DMV-7009AS
			# https://github.com/RFD-FHEM/RFFHEM/issues/195
			# MU;P0=-9808;P1=608;P2=-679;P3=1243;D=012323232323232323232323232323232323232323;CP=3;R=254;
            # MU;P0=-5476;P1=592;P2=-665;P3=1226;P4=-1309;D=012323232323232323232323234123234123234141;CP=3;R=1;
            # MU;P0=-3156;P1=589;P2=-668;P3=1247;P4=-1370;D=012323232323232323232323234123232323234123;CP=3;R=255;
            # MU;P0=-9800;P1=592;P2=-665;P3=1259;P4=-1332;D=012323232323232323232323232341234123232323;CP=3;R=1;
		{   
			name 			=> 'QUIGG_GT-7000',
			comment         => 'remote QUIGG DMV-7000',
			id 		=> '34',
			one             => [-1,2],
			zero            => [-2,1],
			start			=> [1],
			clockabs   		=> '660',
			clockpos		=> ['zero',1],
			format			=> 'twostate', 
			preamble 		=> 'P34#',
			clientmodule 		=> 'SD_UT',
			#modulematch 		=> '',
			length_min 		=> '19',
			length_max 		=> '20',
		},
     "35" => # Homeeasy
			 # MS;P0=907;P1=-376;P2=266;P3=-1001;P6=-4860;D=2601010123230123012323230101012301230101010101230123012301;CP=2;SP=6;
		{   
			name		=> 'HE800',
			comment		=> 'Homeeasy',	
			id          	=> '35',
			one			=> [1,-4],
			zero			=> [3.4,-1],
			sync			=> [1,-18],
			clockabs   		=> '280',		
			format     		=> 'twostate',  		# not used now
			preamble		=> 'ih',				# prepend to converted message	
			postamble		=> '',					# Append to converted message	 	
			clientmodule    => 'IT',
			#modulematch     => '',     			# not used now
			length_min      => '28',
			length_max      => '40',
			postDemodulation => \&SIGNALduino_HE800,
    	},
     "36" =>
     	 {   
			name			=> 'socket36',		
			id          	=> '36',
			one				=> [1,-3],
			zero			=> [1,-1],
			start		 	=> [20,-20],
			clockabs   		=> '500',		
			clockpos		=> ['cp'],
			format     		=> 'twostate',  		# not used now
			preamble		=> 'u36#',				# prepend to converted message	
			postamble		=> '',					# Append to converted message	 	
			#clientmodule    => '',      			# not used now
			#modulematch     => '',     			# not used now
			length_min      => '24',
			length_max      => '24',
    	},
    "37" =>	## Bresser 7009994
			# MU;P0=729;P1=-736;P2=483;P3=-251;P4=238;P5=-491;D=010101012323452323454523454545234523234545234523232345454545232345454545452323232345232340;CP=4;
			# MU;P0=-790;P1=-255;P2=474;P4=226;P6=722;P7=-510;D=721060606060474747472121212147472121472147212121214747212147474721214747212147214721212147214060606060474747472121212140;CP=4;R=216;
			# short pulse of 250 us followed by a 500 us gap is a 0 bit
			# long pulse of 500 us followed by a 250 us gap is a 1 bit
			# sync preamble of pulse, gap, 750 us each, repeated 4 times
     	 {   
			name			=> 'Bresser 7009994',
			comment			=> 'temperature / humidity sensor',
			id      		=> '37',
			one			=> [2,-1],
			zero			=> [1,-2],
			start		 	=> [3,-3,3,-3],
			clockabs   		=> '250',		
			clockpos		=> ['zero',0],
			format     		=> 'twostate',  		# not used now
			preamble		=> 'W37#',				# prepend to converted message	
			clientmodule    => 'SD_WS', 
			length_min      => '40',
			length_max      => '41',
    	},
    "38" => ## Lidl Wetterstation
         	# https://github.com/RFD-FHEM/RFFHEM/issues/63
         	# MS;P1=367;P2=-2077;P4=-9415;P5=-4014;D=141515151515151515121512121212121212121212121212121212121212121212;CP=1;SP=4;O;
      	 {   
			name			=> 'weather38',		
			comment			=> 'temperature / humidity or other sensors',
			id			=> '38',
			one			=> [1,-10],
			zero			=> [1,-5],
			sync 			=> [1,-25],
			clockabs   		=> '360',
			format     		=> 'twostate',  # not used now
			preamble		=> 's',			# prepend to converted message	 	
			postamble		=> '00',		# Append to converted message	 	
			clientmodule    => 'CUL_TCM97001',
			#modulematch     => '^s[A-Fa-f0-9]+', # not used now
			length_min      => '32',
			length_max      => '32',
			paddingbits     => '8',
    	},   
	"39" => ## X10 Protocol
         	# https://github.com/RFD-FHEM/RFFHEM/issues/65
         	# MU;P0=10530;P1=-2908;P2=533;P3=-598;P4=-1733;P5=767;D=0123242323232423242324232324232423242323232324232323242424242324242424232423242424232501232423232324232423242323242324232423232323242323232424242423242424242324232424242325012324232323242324232423232423242324232323232423232324242424232424242423242324242;CP=2;O;
		{
			name => 'X10 Protocol',
			id => '39',
			one => [1,-3],
			zero => [1,-1],
			start => [17,-7],
			clockabs => 560, 
			clockpos => ['cp'],
			format => 'twostate', 
			preamble => '', # prepend to converted message
			clientmodule => 'RFXX10REC',
			#modulematch => '^TX......', # not used now
			length_min => '32',
			length_max => '44',
			paddingbits     => '8',
			postDemodulation => \&SIGNALduino_lengtnPrefix,			
			filterfunc      => 'SIGNALduino_compPattern',
		},    
	"40" => ## Romotec
			# https://github.com/RFD-FHEM/RFFHEM/issues/71
			# MU;P0=300;P1=-772;P2=674;P3=-397;P4=4756;P5=-1512;D=4501232301230123230101232301010123230101230103;CP=0;
			# MU;P0=-132;P1=-388;P2=675;P4=271;P5=-762;D=012145212145452121454545212145452145214545454521454545452145454541;CP=4;
		{
			name => 'romotec',
			comment	=> 'Tubular motor',
			id => '40',
			one => [3,-2],
			zero => [1,-3],
			start => [1,-2],
			clockabs => 250, 
			clockpos => ['zero',0],
			preamble => 'u40#', # prepend to converted message
			#clientmodule => '', # not used now
			#modulematch => '', # not used now
			length_min => '12',
		},    
	"41"	=>	## Elro (Smartwares) Doorbell DB200 / 16 melodies
						# https://github.com/RFD-FHEM/RFFHEM/issues/70
						# MS;P0=-526;P1=1450;P2=467;P3=-6949;P4=-1519;D=231010101010242424242424102424101010102410241024101024241024241010;CP=2;SP=3;O;
						# MS;P0=468;P1=-1516;P2=1450;P3=-533;P4=-7291;D=040101230101010123230101232323012323010101012301232323012301012323;CP=0;SP=4;O;
						# unitec Modell:98156+98YK / 36 melodies
						# repeats 15, change two codes every 15 repeats --> one button push, 2 codes
						# MS;P0=1474;P1=-521;P2=495;P3=-1508;P4=-6996;D=242323232301232323010101230123232301012301230123010123230123230101;CP=2;SP=4;R=51;m=0;
						# MS;P1=-7005;P2=482;P3=-1511;P4=1487;P5=-510;D=212345454523452345234523232345232345232323234523454545234523234545;CP=2;SP=1;R=47;m=2;
						## KANGTAI Doorbell (Pollin 94-550405)
						# https://github.com/RFD-FHEM/RFFHEM/issues/365
						# The bell button alternately sends two different codes
						# P41#BA2885D3: MS;P0=1390;P1=-600;P2=409;P3=-1600;P4=-7083;D=240123010101230123232301230123232301232323230123010101230123230101;CP=2;SP=4;R=248;O;m0;
						# P41#BA2885D3: MS;P0=1399;P1=-604;P2=397;P3=-1602;P4=-7090;D=240123010101230123232301230123232301232323230123010101230123230101;CP=2;SP=4;R=248;O;m1;
						# P41#1791D593: MS;P1=403;P2=-7102;P3=-1608;P4=1378;P5=-620;D=121313134513454545451313451313134545451345134513454513134513134545;CP=1;SP=2;R=5;O;m0;
		{
			name					=> 'wireless doorbell',
			comment				=> 'Elro (DB200) / KANGTAI (Pollin 94-550405) / unitec',
			id						=> '41',
			zero					=> [1,-3],
			one						=> [3,-1],
			sync					=> [1,-14],
			clockabs			=> 500, 
			format				=> 'twostate',
			preamble			=> 'P41#', # prepend to converted message
			clientmodule	=> 'SD_BELL',
			modulematch		=> '^P41#.*',
			length_min		=> '32',
			length_max		=> '32',
		},
	"42"	=>	## Pollin 94-551227
						# https://github.com/RFD-FHEM/RFFHEM/issues/390
						# MU;P0=1446;P1=-487;P2=477;D=0101012121212121212121212101010101212121212121212121210101010121212121212121212121010101012121212121212121212101010101212121212121212121210101010121212121212121212121010101012121212121212121212101010101212121212121212121210101010121212121212121212121010;CP=2;R=93;O;
						# MU;P0=-112;P1=1075;P2=-511;P3=452;P5=1418;D=01212121232323232323232323232525252523232323232323232323252525252323232323232323232325252525;CP=3;R=77; 
		{
			name					=> 'wireless doorbell',
			comment				=> 'Pollin 94-551227',
			id					=> '42',
			one					=> [1,-1],
			zero					=> [3,-1],
			start					=> [1,-1,1,-1,1,-1,],
			clockabs			=> 500,
			clockpos			=> ['one',0],
			format				=> 'twostate',
			preamble			=> 'u42#',
			#clientmodule	=> 'SD_Bell',
			#modulematch		=> '^P42#.*',
			length_min		=> '28',
			length_max		=> '120',
		},
	"43" => ## Somfy RTS
            # MC;LL=-1405;LH=1269;SL=-723;SH=620;D=98DBD153D631BB;C=669;L=56;R=229;
		{
			name 			=> 'Somfy RTS',
			id 				=> '43',
			clockrange  	=> [610,680],			# min , max
			format			=> 'manchester', 
			preamble 		=> 'Ys',
			clientmodule	=> 'SOMFY', # not used now
			modulematch 	=> '^Ys[0-9A-F]{14}',
			length_min 		=> '56',
			length_max 		=> '57',
			method          => \&SIGNALduino_SomfyRTS, # Call to process this message
			msgIntro		=> 'SR;P0=-2560;P1=2560;P3=-640;D=10101010101010113;',
			#msgOutro		=> 'SR;P0=-30415;D=0;',
			frequency		=> '10AB85550A',
		},
	"44" => ## Bresser Temeo Trend
		# MU;P0=-1947;P1=-3891;P2=3880;P3=-478;P4=494;P5=-241;P7=1963;D=34570712171717071707070717071717170707070717170707070707070707170707070717070717071717170717070707171717170707171717171717171707171717170717171707170717;CP=7;R=28;
		{
            		name 			=> 'BresserTemeo',
            		id 			=> '44',
            		clockabs		=> 2000,
            		clockpos		=> ['cp'],
            		zero 			=> [1,-1],
            		one			=> [1,-2],
            		start	 		=> [2,-2],
            		preamble 		=> 'W44#',
            		clientmodule		=> 'SD_WS',
            		modulematch		=> '^W44#[A-F0-9]{18}',
            		length_min 		=> '64',
            		length_max 		=> '72',
		},
	"44.1" => ## Bresser Temeo Trend
		{
            		name 			=> 'BresserTemeo',
            		id 			=> '44',
            		clockabs		=> 500,
            		zero 			=> [4,-4],
            		one			=> [4,-8],
            		start 			=> [8,-12],
            		preamble 		=> 'W44x#',
            		clientmodule		=> 'SD_WS',
            		modulematch		=> '^W44x#[A-F0-9]{18}',
            		length_min 		=> '64',
            		length_max 		=> '72',
		},
    "45"  => #  Revolt 
			 #	MU;P0=-8320;P1=9972;P2=-376;P3=117;P4=-251;P5=232;D=012345434345434345454545434345454545454543454343434343434343434343434543434345434343434545434345434343434343454343454545454345434343454345434343434343434345454543434343434345434345454543454343434543454345434545;CP=3;R=2
		{
			name         => 'Revolt',
			id           => '45',
			one          => [2,-2],
			zero         => [1,-2],
			start        => [83,-3], 
			clockabs     => 120, 
			clockpos     => ['zero',0],
			preamble     => 'r', # prepend to converted message
			clientmodule => 'Revolt', 
			modulematch  => '^r[A-Fa-f0-9]{22}', 
			length_min   => '84',
			length_max   => '120',	
			postDemodulation => sub {	my ($name, @bit_msg) = @_;	my @new_bitmsg = splice @bit_msg, 0,88;	return 1,@new_bitmsg; },
		},    
	"46"	=>	## Berner Garagentorantrieb GA401
						# remote TEDSEN SKX1MD 433.92 MHz - 1 button | settings via 9 switch on battery compartment
						# compatible with doors: BERNER SKX1MD, ELKA SKX1MD, TEDSEN SKX1LC, TEDSEN SKX1
						# https://github.com/RFD-FHEM/RFFHEM/issues/91
						# door open
						# MU;P0=-15829;P1=-3580;P2=1962;P3=-330;P4=245;P5=-2051;D=1234523232345234523232323234523234540023452323234523452323232323452323454023452323234523452323232323452323454023452323234523452323232323452323454023452323234523452323232323452323454023452323234523452323;CP=2;
						# door close
						# MU;P0=-1943;P1=1966;P2=-327;P3=247;P5=-15810;D=01230121212301230121212121230121230351230121212301230121212121230121230351230121212301230121212121230121230351230121212301230121212121230121230351230121212301230121212121230121230351230;CP=1;
		{
			name				=> 'Berner Garagedoor GA401',
			comment				=> 'remote control TEDSEN SKX1MD',
			id					=> '46',
			one					=> [1,-8],
			zero					=> [8,-1],
			start					=> [1,-63],
			clockabs				=> 250,	# -1=auto	
			clockpos				=> ['one',0],
			format					=> 'twostate',	# not used now
			preamble				=> 'P46#',
			clientmodule			=> 'SD_UT',
			modulematch			=> '^P46#.*',
			length_min			=> '16',
			length_max			=> '18',
			},
	"47"	=>	## Maverick
						# MC;LL=-507;LH=490;SL=-258;SH=239;D=AA9995599599A959996699A969;C=248;L=104;
		{
			name				=> 'Maverick',
			comment				=> 'BBQ / food thermometer',
			id				=> '47',
			clockrange     	=> [180,260],
			format 			=> 'manchester',	
			preamble		=> 'P47#',						# prepend to converted message	
			clientmodule    => 'SD_WS_Maverick',   					
			modulematch     => '^P47#[569A]{12}.*',  					
			length_min      => '100',
			length_max      => '108',
			method          => \&SIGNALduino_Maverick,		# Call to process this message
			#polarity		=> 'invert'
		}, 			
     "48"    => ## Joker Dostmann TFA 30.3055.01
				# https://github.com/RFD-FHEM/RFFHEM/issues/92
				# MU;P0=591;P1=-1488;P2=-3736;P3=1338;P4=-372;P6=-988;D=23406060606063606363606363606060636363636363606060606363606060606060606060606060636060636360106060606060606063606363606363606060636363636363606060606363606060606060606060606060636060636360106060606060606063606363606363606060636363636363606060606363606060;CP=0;O;
				# MU;P0=96;P1=-244;P2=510;P3=-1000;P4=1520;P5=-1506;D=01232323232343234343232343234323434343434343234323434343232323232323232323232323234343234325232323232323232343234343232343234323434343434343234323434343232323232323232323232323234343234325232323232323232343234343232343234323434343434343234323434343232323;CP=2;O;
		{
			name			=> 'TFA Dostmann',	
			comment			=> 'Funk-Thermometer Joker TFA 30.3055.01',
			id          	=> '48',
			clockabs     	=> 250, 						# In real it is 500 but this leads to unprceise demodulation 
			clockpos     => ['zero',1],
			one				=> [-4,6],
			zero			=> [-4,2],
			start			=> [-6,2],
			format 			=> 'twostate',	
			preamble		=> 'U48#',						# prepend to converted message	
			#clientmodule    => '',   						# not used now
			modulematch     => '^U48#.*',  					# not used now
			length_min      => '47',
			length_max      => '48',
		}, 			
	"49"    => ## quigg / Aldi gt_9000
			   # https://github.com/RFD-FHEM/RFFHEM/issues/93
               # MU;P0=-563;P1=479;P2=991;P3=-423;P4=361;P5=-1053;P6=3008;P7=-7110;D=2345454523452323454523452323452323452323454545456720151515201520201515201520201520201520201515151567201515152015202015152015202015202015202015151515672015151520152020151520152020152020152020151515156720151515201520201515201520201520201520201515151;CP=1;R=21;
		{
			name		=> 'quigg_gt9000',	
			id          	=> '49',
			clockabs     	=> 400, 						
			clockpos	=> ['zero',0],
			one				=> [2,-1.2],
			zero			=> [1,-3],
			start			=> [6,-15],
			format 			=> 'twostate',	
			preamble		=> 'U49#',						# prepend to converted message	
			#clientmodule    => '',   						# not used now
			modulematch     => '^U49#.*',
			length_min      => '22',
			length_max      => '28',
		}, 
	"50"	=>	## Opus XT300
						# https://github.com/RFD-FHEM/RFFHEM/issues/99
						# MU;P0=248;P1=-21400;P2=545;P3=-925;P4=1368;P5=-12308;D=01232323232323232343234323432343234343434343234323432343434343432323232323232323232343432323432345232323232323232343234323432343234343434343234323432343434343432323232323232323232343432323432345232323232323232343234323432343234343434343234323432343434343;CP=2;O;
		{
			name				=> 'Opus_XT300',
			comment				=> 'sensor for ground humidity',
			id				=> '50',
			clockabs     	=> 500, 						
			clockpos	=> ['one',0],
			zero			=> [3,-2],
			one				=> [1,-2],
		#	start			=> [1,-25],						# Wenn das startsignal empfangen wird, fehlt das 1 bit
			format 			=> 'twostate',	
			preamble		=> 'W50#',						# prepend to converted message	
			clientmodule    => 'SD_WS',
			modulematch     => '^W50#.*',
			length_min      => '47',
			length_max      => '48',
		},
	"51"	=>	## weather sensors
			# MS;P0=-16046;P1=552;P2=-1039;P3=983;P5=-7907;P6=-1841;P7=-4129;D=15161716171616161717171716161616161617161717171717171617171617161716161616161616171032323232;CP=1;SP=5;O;
			# https://github.com/RFD-FHEM/RFFHEM/issues/118
		{  
			name			=> 'weather51',		# Logilink, NC, WS, TCM97001 etc.
			comment			=> 'IAN 275901 Wetterstation Lidl',
			id          	=> '51',
			one				=> [1,-8],
			zero			=> [1,-4],
			sync			=> [1,-13],		
			clockabs   		=> '560',
			format     		=> 'twostate',  # not used now
			preamble		=> 'W51#',		# prepend to converted message	 	
			postamble		=> '',			# Append to converted message	 	
			clientmodule    => 'SD_WS',   
			modulematch     => '^W51#.*',
			length_min      => '40',
			length_max      => '45',
		},
	"52"	=>	## Oregon Scientific PIR Protocol
						# https://forum.fhem.de/index.php/topic,63604.msg548256.html#msg548256
						# MC;LL=-1045;LH=1153;SL=-494;SH=606;D=FFFED518;C=549;L=30;
		{
			name				=> 'Oregon Scientific PIR',
			id				=> '52',
			clockrange     	=> [470,640],			# min , max
			format 			=> 'manchester',	    # tristate can't be migrated from bin into hex!
			clientmodule    => 'OREGON',
			modulematch     => '^u52#F{3}|0{3}.*',
			preamble		=> 'u52#',
			length_min      => '30',
			length_max      => '30',
			method          => \&SIGNALduino_OSPIR, # Call to process this message
			polarity        => 'invert',			
		}, 	
    
	"55"	=>	## QUIGG GT-1000
		{
			name			=> 'QUIGG_GT-1000',
			comment			=> 'remote control',
			id          	=> '55',
			clockabs     	=> 300, 						
			zero			=> [1,-4],
			one				=> [4,-2],
			sync			=> [1,-8],						
			format 			=> 'twostate',	
			preamble		=> 'i',						# prepend to converted message	
			clientmodule    => 'IT',
			modulematch     => '^i.*',
			length_min      => '24',
			length_max      => '24',
		},	
	"56" => ##  Celexon
		{
			name			=> 'Celexon',	
			id          	=> '56',
			clockabs     	=> 200, 						
			clockpos     => ['zero',0],
			zero			=> [1,-3],
			one				=> [3,-1],
			start			=> [25,-3],						
			format 			=> 'twostate',	
			preamble		=> 'u56#',						# prepend to converted message	
			#clientmodule    => ''	,   					# not used now
			#modulematch     => '',  						# not used now
			length_min      => '56',
			length_max      => '68',
		},		
	"57"	=>	## m-e doorbell fuer FG- und Basic-Serie
						# https://forum.fhem.de/index.php/topic,64251.0.html
						# MC;LL=-653;LH=665;SL=-317;SH=348;D=D55B58;C=330;L=21;
						# MC;LL=-654;LH=678;SL=-314;SH=351;D=D55B58;C=332;L=21;
						# MC;LL=-653;LH=679;SL=-310;SH=351;D=D55B58;C=332;L=21;
		{
			name		=> 'm-e',
			comment		=> 'radio gong transmitter for FG- and Basic-Serie',
			id				=> '57',
			clockrange			=> [300,360],						# min , max
			format				=> 'manchester',				# tristate can't be migrated from bin into hex!
			clientmodule		=> 'SD_BELL',
			modulematch			=> '^P57#.*',
			preamble				=> 'P57#',
			length_min      => '21',
			length_max      => '24',
			method          => \&SIGNALduino_MCRAW, # Call to process this message
			polarity        => 'invert',			
		}, 	 
	"58"	=>	## TFA 30.3208.0 
		{
			name		=> 'TFA 30.3208.0',
			comment		=> 'temperature / humidity sensor',
			id          	=> '58',
			clockrange     	=> [460,520],			# min , max
			format 			=> 'manchester',	    # tristate can't be migrated from bin into hex!
			#clientmodule    => '',
			modulematch     => '^W58*',
			preamble		=> 'W58#',
			length_min      => '54',
			length_max      => '136',
			method          => \&SIGNALduino_MCTFA, # Call to process this message
			polarity        => 'invert',			
		}, 	 
	"59"	=>	## AK-HD-4 remote | 4 Buttons
                # https://github.com/RFD-FHEM/RFFHEM/issues/133
                # MU;P0=819;P1=-919;P2=234;P3=-320;P4=8602;P6=156;D=01230301230301230303012123012301230303030301230303412303012303012303030121230123012303030303012303034123030123030123030301212301230123030303030123030341230301230301230303012123012301230303030301230303412303012303012303030121230123012303030303012303034163;CP=0;O;
                # MU;P0=-334;P2=8581;P3=237;P4=-516;P5=782;P6=-883;D=23456305056305050563630563056305050505056305050263050563050563050505636305630563050505050563050502630505630505630505056363056305630505050505630505026305056305056305050563630563056305050505056305050263050563050563050505636305630563050505050563050502630505;CP=5;O;
		{
			name			=> 'AK-HD-4',	
			comment					=> 'remote control with 4 buttons',
			id          	=> '59',
			clockabs     	=> 230, 						
			clockpos     => ['zero',1],
			zero			=> [-4,1],
			one				=> [-1,4],
			start			=> [-1,37],						
			format 			=> 'twostate',	# tristate can't be migrated from bin into hex!
			preamble		=> 'u59#',			# Append to converted message	
			#postamble		=> '',		# Append to converted message	 	
			#clientmodule    => '',   		# not used now
			#modulematch     => '',  # not used now
			length_min      => '24',
			length_max      => '24',
		},			
	"60" =>	## ELV, LA CROSSE (WS2000/WS7000)
			# MU;P0=32001;P1=-381;P2=835;P3=354;P4=-857;D=01212121212121212121343421212134342121213434342121343421212134213421213421212121342121212134212121213421212121343421343430;CP=2;R=53;
			# tested sensors:   WS-7000-20, AS2000, ASH2000, S2000, S2000I, S2001A, S2001IA,
			#                   ASH2200, S300IA, S2001I, S2000ID, S2001ID, S2500H 
			# not tested:       AS3, S2000W, S2000R, WS7000-15, WS7000-16, WS2500-19, S300TH, S555TH
			# das letzte Bit (1) und mehrere Bit (0) Preambel fehlen meistens
			#  ___        _
			# |   |_     | |___
			#  Bit 0      Bit 1
			# kurz 366 mikroSek / lang 854 mikroSek / gesamt 1220 mikroSek - Sollzeiten 
		{
			name                 => 'WS2000',
			comment              => 'Series WS2000/WS7000 of various sensors',
			id                   => '60',
			one                  => [3,-7],	
			zero                 => [7,-3],
			clockabs             => 122,
			clockpos	     => ['one',0],
			pause                => [-70],
			preamble             => 'K',        # prepend to converted message
			#postamble            => '',         # Append to converted message
			clientmodule         => 'CUL_WS',   
			length_min           => '38',       # 46, letztes Bit fehlt = 45, 10 Bit Preambel = 35 Bit Daten
			length_max           => '82',
			postDemodulation     => \&SIGNALduino_postDemo_WS2000,
		}, 

	"61" =>	## ELV FS10
		# tested transmitter:   FS10-S8, FS10-S4, FS10-ZE
		# tested receiver:      FS10-ST, FS10-MS, WS3000-TV, PC-Wettersensor-Empfaenger
		# sends 2 messages with 43 or 48 bits in distance of 100 mS (on/off) , last bit 1 is missing
		# sends x messages with 43 or 48 bits in distance of 200 mS (dimm) , repeats second message
		# MU;P0=1776;P1=-410;P2=383;P3=-820;D=01212121212121212121212123212121232323212323232121212323232121212321212123232123212120;CP=2;R=74;
		#  __         __
		# |  |__     |  |____
		#  Bit 0      Bit 1
		# kurz 400 mikroSek / lang 800 mikroSek / gesamt 800 mikroSek = 0, gesamt 1200 mikroSek = 1 - Sollzeiten 
		{
			name   		=> 'FS10',
			comment        => 'Remote Control (434Mhz)',
			id		=> '61',
			one		=> [1,-2],
			zero		=> [1,-1],
			pause 		=> [-25],
			clockabs	=> 400,
			clockpos	=> ['cp'],
			format 		=> 'twostate',
			preamble	=> 'P61#',      # prepend to converted message
			postamble	=> '',         # Append to converted message
			clientmodule	=> 'FS10',
			#modulematch	=> '',
			length_min	=> '38',	# eigentlich 41 oder 46 (Pruefsumme nicht bei allen)
			length_max      => '48',	# eigentlich 46
		}, 
	"62" => ## Clarus_Switch  
			# MU;P0=-5893;P4=-634;P5=498;P6=-257;P7=116;D=45656567474747474745656707456747474747456745674567456565674747474747456567074567474747474567456745674565656747474747474565670745674747474745674567456745656567474747474745656707456747474747456745674567456565674747474747456567074567474747474567456745674567;CP=7;O;		
		{
			name         => 'Clarus_Switch',
			id           => '62',
			one          => [3,-1],
			zero         => [1,-3],
			start        => [1,-35], # ca 30-40
			clockabs     => 189, 
			clockpos     => ['zero',0],
			preamble     => 'i', # prepend to converted message
			clientmodule => 'IT', 
			#modulematch => '', 
			length_min   => '24',
			length_max   => '24',		
		},
	"63" => ## Warema MU
            # https://forum.fhem.de/index.php/topic,38831.msg395978/topicseen.html#msg395978 | https://www.mikrocontroller.net/topic/264063
			# MU;P0=-2988;P1=1762;P2=-1781;P3=-902;P4=871;P5=6762;P6=5012;D=0121342434343434352434313434243521342134343436;
			# MU;P0=6324;P1=-1789;P2=864;P3=-910;P4=1756;D=0123234143212323232323032321234141032323232323232323;CP=2;
		{
			name         => 'Warema',
			comment      => 'developId, is still experimental',
			id           => '63',
			developId    => 'y',
			one          => [1],
			zero         => [0],
			clockabs     => 800, 
			syncabs		 => '6700',# Special field for filterMC function
			preamble     => 'u63', # prepend to converted message
			#clientmodule => '', 
			#modulematch => '', 
			length_min   => '24',
			filterfunc   => 'SIGNALduino_filterMC',
		},
	"64" => ##  WH2 #############################################################################
			# MU;P0=-32001;P1=457;P2=-1064;P3=1438;D=0123232323212121232123232321212121212121212323212121232321;CP=1;R=63;
			# MU;P0=-32001;P1=473;P2=-1058;P3=1454;D=0123232323212121232123232121212121212121212121232321212321;CP=1;R=51;
			# MU;P0=134;P1=-113;P3=412;P4=-1062;P5=1379;D=01010101013434343434343454345454345454545454345454545454343434545434345454345454545454543454543454345454545434545454345;CP=3;
		{
			name         => 'WH2',
			id           => '64',
			one          => [1,-2],   
			zero			   => [3,-2], 
			clockabs     => 490,
			clockpos	=> ['one',0],
			clientmodule    => 'SD_WS',  
			modulematch  => '^W64*',
			preamble     => 'W64#',       # prepend to converted message
			#postamble    => '',           # Append to converted message       
			#clientmodule => '',
			length_min   => '48',
			length_max   => '54',
		},
	"65" => ## Homeeasy
			# MS;P1=231;P2=-1336;P4=-312;P5=-8920;D=15121214141412121212141414121212121414121214121214141212141212141212121414121414141212121214141214121212141412141212;CP=1;SP=5;
		{
			name         => 'HE_EU',
			comment      => 'Homeeasy',
			id           => '65',
			one          => [1,-5.5],
			zero         => [1,-1.2],
			sync         => [1,-38],
			clockabs     => 230,
			format       => 'twostate',  # not used now
			preamble     => 'ih',
			clientmodule => 'IT',
			length_min   => '57',
			length_max   => '72',
			postDemodulation => \&SIGNALduino_HE_EU,
		},
	"66"	=>	## TX2 Protocol (Remote Temp Transmitter & Remote Thermo Model 7035)
						# https://github.com/RFD-FHEM/RFFHEM/issues/160
						# MU;P0=13312;P1=-2785;P2=4985;P3=1124;P4=-6442;P5=3181;P6=-31980;D=0121345434545454545434545454543454545434343454543434545434545454545454343434545434343434545621213454345454545454345454545434545454343434545434345454345454545454543434345454343434345456212134543454545454543454545454345454543434345454343454543454545454545;CP=3;R=73;O;
		{
			name         => 'WS7035',
			id           => '66',
			one          => [10,-52],
			zero         => [27,-52],
			start        => [-21,42,-21],
			clockabs     => 122,
			clockpos     => ['one',0],
			format       => 'pwm',  # not used now
			preamble     => 'TX',
			clientmodule => 'CUL_TX',
			modulematch  => '^TX......',
			length_min   => '43',
			length_max   => '44',
			postDemodulation => \&SIGNALduino_postDemo_WS7035,
		},
	"67"	=>	## TX2 Protocol (Remote Datalink & Remote Thermo Model 7053, 7054)
						# https://github.com/RFD-FHEM/RFFHEM/issues/162
						# MU;P0=3381;P1=-672;P2=-4628;P3=1142;P4=-30768;D=010 2320232020202020232020232020202320232323202323202020202020202020 4 010 2320232020202020232020232020202320232323202323202020202020202020 0;CP=0;R=45;
						# MU;P0=1148;P1=3421;P6=-664;P7=-4631;D=161 7071707171717171707171707171717171707070717071717171707071717171 0;CP=1;R=29;
						# Message repeats 4 x with pause of ca. 30-34 mS
						#           __               ____
						#  ________|  |     ________|    |
						#      Bit 1             Bit 0
						#    4630  1220       4630   3420   mikroSek - mit Oszi gemessene Zeiten
		{
				name             => 'WS7053',	
				id               => '67',
				one              => [-38,10],     # -4636, 1220
				zero             => [-38,28],     # -4636, 3416
				clockabs         => 122,
				clockpos       => ['one',1],
				preamble         => 'TX',         # prepend to converted message
				clientmodule     => 'CUL_TX',
				modulematch      => '^TX......',
				length_min       => '32',
				length_max       => '34',
				postDemodulation => \&SIGNALduino_postDemo_WS7053,
		},
	"68"	=>	## Pollin PFR-130 ###########################################################################
						# MS;P0=-3890;P1=386;P2=-2191;P3=-8184;D=1312121212121012121212121012121212101012101010121012121210121210101210101012;CP=1;SP=3;R=20;O;
						# MS;P0=-2189;P1=371;P2=-3901;P3=-8158;D=1310101010101210101010101210101010121210121212101210101012101012121012121210;CP=1;SP=3;R=20;O;
		{
			name					=> 'Pollin PFR-130',
			comment				=> 'temperature sensor with rain',
			id						=> '68',
			one						=> [1,-10],
			zero					=> [1,-5],
			sync					=> [1,-21],	
			clockabs			=> 380,
			preamble			=> 's',				# prepend to converted message
			postamble			=> '00',			# Append to converted message
			clientmodule	=> 'CUL_TCM97001',
			length_min		=> '36',
			length_max		=> '42',
			paddingbits		=> '8',				 # pad up to 8 bits, default is 4
		}, 	
	"69"	=>	## Hoermann HSM2, HSM4, HS1-868-BS (868 MHz)
						# https://github.com/RFD-FHEM/RFFHEM/issues/149
						# MU;P0=-508;P1=1029;P2=503;P3=-1023;P4=12388;D=01010232323232310104010101010101010102323231010232310231023232323231023101023101010231010101010232323232310104010101010101010102323231010232310231023232323231023101023101010231010101010232323232310104010101010101010102323231010232310231023232323231023101;CP=2;R=37;O;
						# Remote control HS1-868-BS (one button):
						# https://github.com/RFD-FHEM/RFFHEM/issues/344
						# MU;P0=-578;P1=1033;P2=506;P3=-1110;P4=13632;D=0101010232323101040101010101010101023232323102323101010231023102310231010232323101010101010101010232323101040101010101010101023232323102323101010231023102310231010232323101010101010101010232323101040101010101010101023232323102323101010231023102310231010;CP=2;R=77;
						# MU;P0=-547;P1=1067;P2=553;P3=-1066;P4=13449;D=0101010101010232323101040101010101010101023232323102323101010231023102310231010232323101010101010101010232323101040101010101010101023232323102323101010231023102310231010232323101010101010101010232323101040101010101010101023232323102323101010231023102310;CP=2;R=71;	
						# https://forum.fhem.de/index.php/topic,71877.msg642879.html (HSM4, Taste 1-4)
						# MU;P0=-332;P1=92;P2=-1028;P3=12269;P4=-510;P5=1014;P6=517;D=01234545454545454545462626254546262546254626262626254625454625454546254545454546262626262545434545454545454545462626254546262546254626262626254625454625454546254545454546262626262545434545454545454545462626254546262546254626262626254625454625454546254545;CP=6;R=37;O;
						# MU;P0=509;P1=-10128;P2=1340;P3=-517;P4=1019;P5=-1019;P6=12372;D=01234343434343434343050505434305054305430505050505430543430543434305434343430543050505054343634343434343434343050505434305054305430505050505430543430543434305434343430543050505054343634343434343434343050505434305054305430505050505430543430543434305434343;CP=0;R=52;O;
						# MU;P0=12376;P1=360;P2=-10284;P3=1016;P4=-507;P6=521;P7=-1012;D=01234343434343434343467676734346767346734676767676734673434673434346734343434676767346767343404343434343434343467676734346767346734676767676734673434673434346734343434676767346767343404343434343434343467676734346767346734676767676734673434673434346734343;CP=6;R=55;O;
						# MU;P0=-3656;P1=12248;P2=-519;P3=1008;P4=506;P5=-1033;D=01232323232323232324545453232454532453245454545453245323245323232453232323245453245454532321232323232323232324545453232454532453245454545453245323245323232453232323245453245454532321232323232323232324545453232454532453245454545453245323245323232453232323;CP=4;R=48;O;
		{
			name		=> 'Hoermann',
			comment		=> 'remote control HS1-868-BS, HSM4',
			id              => '69',
			zero            => [2,-1],
			one             => [1,-2],
			start           => [25,-1],  # 24
			clockabs        => 510,
			clockpos	=> ['one',0],
			format          => 'twostate',  # not used now
			clientmodule    => 'SD_UT',
			#modulematch     => '^U69*',
			preamble        => 'P69#',
			length_min      => '40',
			length_max      => '44',
		},
	"70"	=>	## FHT80TF (Funk-Tuer-Fenster-Melder FHT 80TF und FHT 80TF-2)
						# https://github.com/RFD-FHEM/RFFHEM/issues/171	
	# closed MU;P0=-24396;P1=417;P2=-376;P3=610;P4=-582;D=012121212121212121212121234123434121234341212343434121234123434343412343434121234341212121212341212341234341234123434;CP=1;R=35;
	# open   MU;P0=-21652;P1=429;P2=-367;P4=634;P5=-555;D=012121212121212121212121245124545121245451212454545121245124545454512454545121245451212121212124512451245451245121212;CP=1;R=38;
		{
			name         	=> 'FHT80TF',
			comment		   => 'Door/Window switch (868Mhz)',
			id           	=> '70',
			one         	=> [1.5,-1.5],	# 600
			zero         	=> [1,-1],	# 400
			clockabs     	=> 400,
			clockpos	=> ['zero',0],
			format          => 'twostate',  # not used now
			clientmodule    => 'CUL_FHTTK',
			preamble     	=> 'T',
			length_min     => '50',
			length_max     => '58',
			postDemodulation => \&SIGNALduino_postDemo_FHT80TF,
		},
	"71" => ## PV-8644 infactory Poolthermometer
		# MU;P0=1735;P1=-1160;P2=591;P3=-876;D=0123012323010101230101232301230123010101010123012301012323232323232301232323232323232323012301012;CP=2;R=97;
		{
			name		=> 'PV-8644',
			comment		=> 'infactory Poolthermometer',
			id         	=> '71',
			clockabs	=> 580,
			clockpos	=> ['one',0],
			zero		=> [3,-2],
			one		=> [1,-1.5],
			format		=> 'twostate',	
			preamble	=> 'W71#',		# prepend to converted message	
			clientmodule    => 'SD_WS',
			#modulematch     => '^W71#.*'
			length_min      => '48',
			length_max      => '48',
		},
	"72" => # Siro blinds MU    @Dr. Smag
			# ! same definition how ID 16 !
			# https://forum.fhem.de/index.php?topic=77167.0
			# MU;P0=-760;P1=334;P2=693;P3=-399;P4=-8942;P5=4796;P6=-1540;D=01010102310232310101010102310232323101010102310101010101023102323102323102323102310101010102310232323101010102310101010101023102310231023102456102310232310232310231010101010231023232310101010231010101010102310231023102310245610231023231023231023101010101;CP=1;R=45;O;
			# MU;P0=-8848;P1=4804;P2=-1512;P3=336;P4=-757;P5=695;P6=-402;D=0123456345656345656345634343434345634565656343434345634343434343456345634563456345;CP=3;R=49;	
		{
			name			=> 'Siro shutter',
			id				=> '72',
			dispatchequals  =>  'true',
			one				=> [2,-1.2],    # 680, -400
			zero			=> [1,-2.2],    # 340, -750
			start			=> [14,-4.4],   # 4800,-1520
			clockabs		=> 340,
			clockpos     		=> ['zero',0],
			format 			=> 'twostate',	  		
			preamble		=> 'P72#',		# prepend to converted message	
			clientmodule	=> 'Siro',
			#modulematch 	=> '',  			
			length_min   	=> '39',
			length_max   	=> '40',
			msgOutro		=> 'SR;P0=-8500;D=0;',
		},
 	"72.1" => # Siro blinds MS     @Dr. Smag
			  # MS;P0=4803;P1=-1522;P2=333;P3=-769;P4=699;P5=-393;P6=-9190;D=2601234523454523454523452323232323452345454523232323452323232323234523232345454545;CP=2;SP=6;R=61;
		{
			name			=> 'Siro shutter',
			comment     	=> 'developModule. Siro is not in github',
			id				=> '72',
			developId		=> 'm',
			dispatchequals  =>  'true',
			one				=> [2,-1.2],    # 680, -400
			zero			=> [1,-2.2],    # 340, -750
			sync			=> [14,-4.4],   # 4800,-1520
			clockabs		=> 340,
			clockpos		=> ['zero',0],
			format 			=> 'twostate',	  		
			preamble		=> 'P72#',		# prepend to converted message	
			clientmodule	=> 'Siro',
			#modulematch 	=> '',  			
			length_min   	=> '39',
			length_max   	=> '40',
			#msgOutro	=> 'SR;P0=-8500;D=0;',
		},
	"73" => ## FHT80 - Raumthermostat (868Mhz),  @HomeAutoUser
			# MU;P0=136;P1=-112;P2=631;P3=-392;P4=402;P5=-592;P6=-8952;D=0123434343434343434343434325434343254325252543432543434343434325434343434343434343254325252543254325434343434343434343434343252525432543464343434343434343434343432543434325432525254343254343434343432543434343434343434325432525254325432543434343434343434;CP=4;R=250;
		{
			name		=> 'FHT80',
			comment 	=> 'Roomthermostat (868Mhz only receive)',
			id		=> '73',
			developId	=> 'y',
			one		=> [1.5,-1.5], # 600
			zero		=> [1,-1], # 400
			pause			=> [-25],
			clockabs	=> 400,
			clockpos	=> ['zero',0],
			format		=> 'twostate', # not used now
			clientmodule	=> 'FHT',
			preamble	=> '810c04xx0909a001',
			length_min	=> '59',
			length_max	=> '67',
			postDemodulation => \&SIGNALduino_postDemo_FHT80,
		},
	"74"	=>	## FS20 - 'Remote Control (868Mhz),  @HomeAutoUser
						# MU;P0=-10420;P1=-92;P2=398;P3=-417;P5=596;P6=-592;D=1232323232323232323232323562323235656232323232356232356232623232323232323232323232323235623232323562356565623565623562023232323232323232323232356232323565623232323235623235623232323232323232323232323232323562323232356235656562356562356202323232323232323;CP=2;R=72;
		{
			name			=> 'FS20',
			comment			=> 'Remote Control (868Mhz)',
			id			=> '74',
			one			=> [1.5,-1.5], # 600
			zero			=> [1,-1], # 400
			pause			=> [-25],
			clockabs		=> 400,
			clockpos		=> ['zero',0],
			format			=> 'twostate', # not used now
			clientmodule		=> 'FS20',
			preamble		=> '810b04f70101a001',
			length_min		=> '50',
			length_max		=> '67',
			postDemodulation => \&SIGNALduino_postDemo_FS20,
		},
	"75"	=>	## Conrad RSL (Erweiterung v2) @litronics https://github.com/RFD-FHEM/SIGNALDuino/issues/69
						# ! same definition how ID 5, but other length !
						# !! protocol needed revision - start or sync failed !! https://github.com/RFD-FHEM/SIGNALDuino/issues/69#issuecomment-440349328
						# MU;P0=-1365;P1=477;P2=1145;P3=-734;P4=-6332;D=01023202310102323102423102323102323101023232323101010232323231023102323102310102323102423102323102323101023232323101010232323231023102323102310102323102;CP=1;R=12;
		{
			name					=> 'Conrad RSL v2',
			comment				=> 'remotes and switches',
			id			=> '75',
			one			=> [3,-1],
			zero			=> [1,-3],
			clockabs		=> 500, 
			clockpos		=> ['zero',0],
			format			=> 'twostate', 
			developId		=> 'y',
			clientmodule		=> 'SD_RSL',
			preamble		=> 'P1#',  
			modulematch		=> '^P1#[A-Fa-f0-9]{8}', 
			length_min		=> '32',
			length_max 		=> '40',
		},
	"76"	=>	## Kabellose LED-Weihnachtskerzen XM21-0
		{
			name					=> 'LED XM21',
			comment				=> 'reserviert, LED Lichtrekette on',
			id						=> '76',
			developId			=> 'p',
			one						=> [1.2,-2],			# 120,-200
			zero					=> [],						# existiert nicht
			start					=> [4.5,-2],			# 450,-200 Starsequenz
			clockabs			=> 100,
			format				=> 'twostate',		# not used now
			clientmodule	=> '',
			preamble			=> 'P76',
			length_min		=> 64,
			length_max		=> 64,
		},
	"76.1"	=>	## Kabellose LED-Weihnachtskerzen XM21-0
		{
			name					=> 'LED XM21',
			comment				=> 'reserviert, LED Lichtrekette off',
			id						=> '76.1',
			developId			=> 'p', 
			one						=> [1.2,-2],			# 120,-200
			zero					=> [],						# existiert nicht
			start					=> [4.5,-2],			# 450,-200 Starsequenz
			clockabs			=> 100,
			format				=> 'twostate',		# not used now
			clientmodule	=> '',
			preamble			=> 'P76',
			length_min		=> 58,
			length_max		=> 58,
		},
	"77"	=>	## https://github.com/juergs/NANO_DS1820_4Fach
						# MU;P0=102;P1=236;P2=-2192;P3=971;P6=-21542;D=01230303030103010303030303010103010303010303010101030301030103030303010101030301030303010163030303010301030303030301010301030301030301010103030103010303030301010103030103030301016303030301030103030303030101030103030103030101010303010301030303030101010303;CP=0;O;
						# MU;P0=-1483;P1=239;P2=970;P3=-21544;D=01020202010132020202010201020202020201010201020201020201010102020102010202020201010102020102020201013202020201020102020202020101020102020102020101010202010201020202020101010202010202020101;CP=1;
						# MU;P0=-168;P1=420;P2=-416;P3=968;P4=-1491;P5=242;P6=-21536;D=01234343434543454343434343454543454345434543454345434343434343434343454345434343434345454363434343454345434343434345454345434543454345434543434343434343434345434543434343434545436343434345434543434343434545434543454345434543454343434343434343434543454343;CP=3;O;
						# MU;P0=-1483;P1=969;P2=236;P3=-21542;D=01010102020131010101020102010101010102020102010201020102010201010101010101010102010201010101010202013101010102010201010101010202010201020102010201020101010101010101010201020101010101020201;CP=1;
						# MU;P0=-32001;P1=112;P2=-8408;P3=968;P4=-1490;P5=239;P6=-21542;D=01234343434543454343434343454543454345454343454345434343434343434343454345434343434345454563434343454345434343434345454345434545434345434543434343434343434345434543434343434545456343434345434543434343434545434543454543434543454343434343434343434543454343;CP=3;O;
						# MU;P0=-1483;P1=968;P2=240;P3=-21542;D=01010102020231010101020102010101010102020102010202010102010201010101010101010102010201010101010202023101010102010201010101010202010201020201010201020101010101010101010201020101010101020202;CP=1;
						# MU;P0=-32001;P1=969;P2=-1483;P3=237;P4=-21542;D=01212121232123212121212123232123232121232123212321212121212121212123212321212121232123214121212123212321212121212323212323212123212321232121212121212121212321232121212123212321412121212321232121212121232321232321212321232123212121212121212121232123212121;CP=1;O;
						# MU;P0=-1485;P1=967;P2=236;P3=-21536;D=010201020131010101020102010101010102020102020101020102010201010101010101010102010201010101020102013101010102010201010101010202010202010102010201020101010101010101010201020101010102010201;CP=1;
		{
			name					=> 'NANO_DS1820_4Fach',
			comment				=> 'self build sensor',
			id						=> '77',
			developId			=> 'y', 
			zero					=> [4,-6],
			one						=> [1,-6],
			clockabs			=> 250,
			clockpos			=> ['one',0],
			format				=> 'pwm',				#
			preamble			=> 'TX',				# prepend to converted message
			clientmodule	=> 'CUL_TX',
			modulematch		=> '^TX......',
			length_min		=> '43',
			length_max		=> '44',
			remove_zero		=> 1,						# Removes leading zeros from output
		},
	"78"	=>	## geiger blind motors
						# MU;P0=313;P1=1212;P2=-309;P4=-2024;P5=-16091;P6=2014;D=01204040562620404626204040404040462046204040562620404626204040404040462046204040562620404626204040404040462046204040562620404626204040404040462046204040;CP=0;R=236;)
						# https://forum.fhem.de/index.php/topic,39153.0.html
		{
			name			=> 'geiger',
			comment			=> 'geiger blind motors',
			id				=> '78',
			developId		=> 'y',
			zero			=> [1,-6.6], 		
			one				=> [6.6,-1],   		 
			start  			=> [-53],		
			clockabs     	=> 300,					 
			clockpos     => ['zero',0],
			format 			=> 'twostate',	     
			preamble		=> 'u78#',			# prepend to converted message	
			clientmodule    => 'SIGNALduino_un',   	
			#modulematch	=> '^TX......', 
			length_min      => '14',
			length_max      => '18',
			paddingbits     => '2'				 # pad 1 bit, default is 4
		},
	"79"	=>	## Heidemann | Heidemann HX | VTX-BELL
						# https://github.com/RFD-FHEM/SIGNALDuino/issues/84
						# MU;P0=656;P1=-656;P2=335;P3=-326;P4=-5024;D=0123012123012303030301 24 230123012123012303030301 24 230123012123012303030301 24 2301230121230123030303012423012301212301230303030124230123012123012303030301242301230121230123030303012423012301212301230303030124230123012123012303030301242301230121230123030303;CP=2;O;
						# https://forum.fhem.de/index.php/topic,64251.0.html
						# MU;P0=540;P1=-421;P2=-703;P3=268;P4=-4948;D=4 323102323101010101010232 34 323102323101010101010232 34 323102323101010101010232 34 3231023231010101010102323432310232310101010101023234323102323101010101010232343231023231010101010102323432310232310101010101023234323102323101010101010232343231023231010101010;CP=3;O;
						# https://github.com/RFD-FHEM/RFFHEM/issues/252
						# MU;P0=-24096;P1=314;P2=-303;P3=615;P4=-603;P5=220;P6=-4672;D=0123456123412341414141412323234 16 123412341414141412323234 16 12341234141414141232323416123412341414141412323234161234123414141414123232341612341234141414141232323416123412341414141412323234161234123414141414123232341612341234141414141232323416123412341414;CP=1;R=26;O;
						# MU;P0=-10692;P1=602;P2=-608;P3=311;P4=-305;P5=-4666;D=01234123232323234141412 35 341234123232323234141412 35 341234123232323234141412 35 34123412323232323414141235341234123232323234141412353412341232323232341414123534123412323232323414141235341234123232323234141412353412341232323232341414123534123412323232323414;CP=3;R=47;O;
						# MU;P0=-7152;P1=872;P2=-593;P3=323;P4=-296;P5=622;P6=-4650;D=01234523232323234545452 36 345234523232323234545452 36 345234523232323234545452 36 34523452323232323454545236345234523232323234545452363452345232323232345454523634523452323232323454545236345234523232323234545452363452345232323232345454523634523452323232323454;CP=3;R=26;O;
		{
			name					=> 'wireless doorbell',
			comment				=> 'Heidemann | Heidemann HX | VTX-BELL',
			id		=> '79',
			zero		=> [-2,1],
			one		=> [-1,2],
			start  		=> [-15,1],
			clockabs     	=> 330,
			clockpos        => ['zero',1],
			format				=> 'twostate',	# 
			preamble			=> 'P79#',			# prepend to converted message
			clientmodule	=> 'SD_BELL',
			modulematch		=> '^P79#.*',
			length_min		=> '12',
			length_max		=> '12',
		},
	"80"	=>	## EM1000WZ (Energy-Monitor) Funkprotokoll (868Mhz),  @HomeAutoUser | Derwelcherichbin
						# https://github.com/RFD-FHEM/RFFHEM/issues/253
						# MU;P1=-417;P2=385;P3=-815;P4=-12058;D=42121212121212121212121212121212121232321212121212121232321212121212121232323212323212321232121212321212123232121212321212121232323212121212121232121212121212121232323212121212123232321232121212121232123232323212321;CP=2;R=87;
		{	
			name			=> 'EM (Energy-Monitor)',
			comment         => 'EM (Energy-Monitor) (868Mhz)',
			id				=> '80',
			one             => [1,-2],	# 800
			zero			=> [1,-1],	# 400
			clockabs		=> 400,
			format			=> 'twostate', # not used now
			clientmodule	=> 'CUL_EM',
			preamble        => 'E',
			length_min		=> '104',
			length_max		=> '114',
			postDemodulation => \&SIGNALduino_postDemo_EM,
		},
	"81" => ## Remote control SA-434-1 based on HT12E @ elektron-bbs
			# MU;P0=-485;P1=188;P2=-6784;P3=508;P5=1010;P6=-974;P7=-17172;D=0123050505630505056305630563730505056305050563056305637305050563050505630563056373050505630505056305630563730505056305050563056305637305050563050505630563056373050505630505056305630563730505056305050563056305637305050563050505630563056373050505630505056;CP=3;R=0;
			# MU;P0=-1756;P1=112;P2=-11752;P3=496;P4=-495;P5=998;P6=-988;P7=-17183;D=0123454545634545456345634563734545456345454563456345637345454563454545634563456373454545634545456345634563734545456345454563456345637345454563454545634563456373454545634545456345634563734545456345454563456345637345454563454545634563456373454545634545456;CP=3;R=0;
			#      __        ____
			# ____|  |    __|    |
			#  Bit 1       Bit 0
			# short 500 microSec / long 1000 microSec / bittime 1500 mikroSek / pilot 12 * bittime, from that 1/3 bitlength high
		{
			name             => 'SA-434-1',
			comment          => 'Remote control SA-434-1 mini 923301 based on HT12E (developModule SD_UT is only in github available)',
			id               => '81',
			one              => [-2,1],			# i.O.
			zero             => [-1,2],			# i.O.
			start            => [-35,1],		# Message is not provided as MS, worakround is start
			clockabs		 => 500,                 
			clockpos         => ['one',1],
			format           => 'twostate',
			preamble	     => 'P81#',			# prepend to converted message
			modulematch      => '^P81#.{3}',
			clientmodule	 => 'SD_UT',
			length_min       => '12',
			length_max       => '12',
		},
	"82" => ## Fernotron shutters and light switches   
			# MU;P0=-32001;P1=435;P2=-379;P4=-3201;P5=831;P6=-778;D=01212121212121214525252525252521652161452525252525252161652141652521652521652521614165252165252165216521416521616165216525216141652161616521652165214165252161616521652161416525216161652161652141616525252165252521614161652525216525216521452165252525252525;CP=1;O;
			# the messages received are usual missing 12 bits at the end for some reason. So the checksum byte is missing.
			# Fernotron protocol is unidirectional. Here we can only receive messages from controllers send to receivers.
			# https://github.com/RFD-FHEM/RFFHEM/issues/257
		{
			name           => 'Fernotron',
			id             => '82',       # protocol number
			developId      => 'm',
			dispatchBin    => 'y',
			one            => [1,-2],     # on=400us, off=800us
			zero           => [2,-1],     # on=800us, off=400us
			float          => [1,-8],     # on=400us, off=3200us. the preamble and each 10bit word has one [1,-8] in front
			pause          => [1,-1],     # preamble (7x)
			clockabs       => 400,        # 400us
			clockpos       => ['one',0],
			format         => 'twostate',
			preamble       => 'P82#',     # prepend our protocol number to converted message
			clientmodule   => 'Fernotron',
			length_min     => '100',      # actual 120 bit (12 x 10bit words to decode 6 bytes data), but last 20 are for checksum
			length_max     => '3360',     # 3360 bit (336 x 10bit words to decode 168 bytes data) for full timer message
	    },
	"83" => ## Remote control RH787T based on MOSDESIGN SEMICONDUCTOR CORP (CMOS ASIC encoder) M1EN compatible HT12E
			# for example Westinghouse Deckenventilator Delancey, 6 speed buttons, @zwiebelxxl
			# https://github.com/RFD-FHEM/RFFHEM/issues/250
			# Taste 1 MU;P0=388;P1=-112;P2=267;P3=-378;P5=585;P6=-693;P7=-11234;D=0123035353535356262623562626272353535353562626235626262723535353535626262356262627235353535356262623562626272353535353562626235626262723535353535626262356262627235353535356262623562626272353535353562626235626262723535353535626262356262627235353535356262;CP=2;R=43;O;
			# Taste 2 MU;P0=-176;P1=262;P2=-11240;P3=112;P5=-367;P6=591;P7=-695;D=0123215656565656717171567156712156565656567171715671567121565656565671717156715671215656565656717171567156712156565656567171715671567121565656565671717156715671215656565656717171567156712156565656567171715671567121565656565671717171717171215656565656717;CP=1;R=19;O;
			# Taste 3 MU;P0=564;P1=-392;P2=-713;P3=245;P4=-11247;D=0101010101023231023232323431010101010232310232323234310101010102323102323232343101010101023231023232323431010101010232310232323234310101010102323102323232343101010101023231023232323431010101010232310232323234310101010102323102323232343101010101023231023;CP=3;R=40;O;
		{
			name		=> 'RH787T',	
			comment         => 'Remote control for example Westinghouse Delancey 7800140 (developModule SD_UT is only in github available)',
			id          	=> '83',
			one				=> [-2,1],
			zero			=> [-1,2],
			start			=> [-35,1],				# calculated 12126,31579 µS
			clockabs		=> 335,                 # calculated ca 336,8421053 µS short - 673,6842105µS long 
			clockpos     		=> ['one',1],
			format 			=> 'twostate',	  		# there is a pause puls between words
			preamble		=> 'P83#',				# prepend to converted message	
			clientmodule    => 'SD_UT', 
			modulematch     => '^P83#.{3}',
			length_min      => '12',
			length_max      => '12',
		},
	"84"	=>	## Funk Wetterstation Auriol IAN 283582 Version 06/2017 (Lidl), Modell-Nr.: HG02832D, 09/2018@roobbb
						# https://github.com/RFD-FHEM/RFFHEM/issues/263
						# MU;P0=-28796;P1=376;P2=-875;P3=834;P4=220;P5=-632;P6=592;P7=-268;D=0123232324545454545456767454567674567456745674545454545456767676767674567674567676767456;CP=4;R=22;
						# MU;P0=-28784;P1=340;P2=-903;P3=814;P4=223;P5=-632;P6=604;P7=-248;D=0123232324545454545456767456745456767674545674567454545456745454545456767454545456745676;CP=4;R=22;
						# MU;P0=-21520;P1=235;P2=-855;P3=846;P4=620;P5=-236;P7=-614;D=012323232454545454545451717451717171745171717171717171717174517171745174517174517174545;CP=1;R=217;
						## Sempre 92596/65395, Hofer/Aldi, WS97210-1, WS97230-1, WS97210-2, WS97230-2
						# https://github.com/RFD-FHEM/RFFHEM/issues/223
						# MU;P0=11916;P1=-852;P2=856;P3=610;P4=-240;P5=237;P6=-610;D=01212134563456563434565634565634343456565634565656565634345634565656563434563456343430;CP=5;R=254;
						# MU;P0=-30004;P1=815;P2=-910;P3=599;P4=-263;P5=234;P6=-621;D=0121212345634565634345656345656343456345656345656565656343456345634563456343434565656;CP=5;R=5;
		{
			name					=> 'IAN 283582',
			comment				=> 'Weatherstation Auriol IAN 283582 / Sempre 92596/65395',
			id						=> '84',
			one						=> [3,-1],
			zero					=> [1,-3],
			start					=> [4,-4,4,-4,4,-4],
			clockabs			=> 215, 
			clockpos			=> ['zero',0],
			format				=> 'twostate',
			preamble			=> 'W84#',						# prepend to converted message
			postamble			=> '',								# append to converted message
			clientmodule	=> 'SD_WS',
			length_min		=> '39',							# das letzte Bit fehlt meistens
			length_max		=> '40',
		},
	"85"	=>	## Funk Wetterstation TFA 35.1140.01 mit Temperatur-/Feuchte- und Windsensor TFA 30.3222.02 09/2018@Iron-R
						# https://github.com/RFD-FHEM/RFFHEM/issues/266
						# MU;P0=-509;P1=474;P2=-260;P3=228;P4=718;P5=-745;D=01212303030303012301230123012301230301212121230454545453030303012123030301230303012301212123030301212303030303030303012303012303012303012301212303030303012301230123012301230301212121212454545453030303012123030301230303012301212123030301212303030303030303;CP=3;R=46;O;
						# MU;P0=-504;P1=481;P2=-254;P3=227;P4=723;P5=-739;P6=-1848;D=01230121212303030121230303030303030453030303012123030301230303012301212303030303030304530303030121230303012303030123012121230303012123030303030303030123030123030123030123012123030303030123012301230123012303012121212364545454530303030121230303012303030123;CP=3;R=45;O;
						# MU;P0=7944;P1=-724;P2=742;P3=241;P4=-495;P5=483;P6=-248;D=01212121343434345656343434563434345634565656343434565634343434343434345634345634345634343434343434343434345634565634345656345634343456563421212121343434345656343434563434345634565656343434565634343434343434345634345634345634343434343434343434345634565634;CP=3;R=47;O;�
		{
			name					=> 'TFA 30.3222.02',
			comment				=> 'Combisensor for Weatherstation TFA 35.1140.01',
			id						=> '85',
			one						=> [2,-1],
			zero					=> [1,-2],
			start					=> [3,-3,3,-3,3,-3],
			clockabs			=> 250, 
			clockpos			=> ['zero',0],
			format				=> 'twostate',
			preamble			=> 'W85#',					# prepend to converted message
			#postamble			=> '',							# append to converted message
			clientmodule	=> 'SD_WS',
			length_min		=> '64',
			length_max		=> '68',
		},
	"86"	=>	### for remote controls:  Novy 840029, CAME TOP 432EV, OSCH & Neff Transmitter SF01 01319004
						### CAME TOP 432EV 433,92 MHz für z.B. Drehtor Antrieb:
						# https://forum.fhem.de/index.php/topic,63370.msg849400.html#msg849400
						# https://github.com/RFD-FHEM/RFFHEM/issues/151
						# MU;P0=711;P1=-15288;P4=132;P5=-712;P6=316;P7=-313;D=4565656705656567056567056 16 565656705656567056567056 16 56565670565656705656705616565656705656567056567056165656567056565670565670561656565670565656705656705616565656705656567056567056165656567056565670565670561656565670565656705656705616565656705656567056;CP=6;R=52;
						# MU;P0=-322;P1=136;P2=-15241;P3=288;P4=-735;P6=723;D=012343434306434343064343430623434343064343430643434306 2343434306434343064343430 623434343064343430643434306234343430643434306434343062343434306434343064343430623434343064343430643434306234343430643434306434343062343434306434343064343430;CP=3;R=27;
						# MU;P0=-15281;P1=293;P2=-745;P3=-319;P4=703;P5=212;P6=152;P7=-428;D=0 1212121342121213421213421 01 212121342121213421213421 01 21212134212121342121342101212121342121213421213421012121213421212134212134210121243134212121342121342101252526742121213425213421012121213421212134212134210121212134212;CP=1;R=23;
						# rechteTaste: 0x112 (000100010010), linkeTaste: 0x111 (000100010001), the least significant bits distinguish the keys
						### remote control Novy 840029 for Novy Pureline 6830 kitchen hood:
						# https://github.com/RFD-FHEM/RFFHEM/issues/331
						# light on/off button  # MU;P0=710;P1=353;P2=-403;P4=-761;P6=-16071;D=20204161204120412041204120414141204120202041612041204120412041204141412041202020416120412041204120412041414120412020204161204120412041204120414141204120202041;CP=1;R=40;
						# plus button          # MU;P0=22808;P1=-24232;P2=701;P3=-765;P4=357;P5=-15970;P7=-406;D=012345472347234723472347234723454723472347234723472347234547234723472347234723472345472347234723472347234723454723472347234723472347234;CP=4;R=39;
						# minus button         # MU;P0=-8032;P1=364;P2=-398;P3=700;P4=-760;P5=-15980;D=0123412341234123412341412351234123412341234123414123512341234123412341234141235123412341234123412341412351234123412341234123414123;CP=1;R=40;
						# power button         # MU;P0=-756;P1=718;P2=354;P3=-395;P4=-16056;D=01020202310231310202 42 310231023102310231020202310231310202 42 31023102310231023102020231023131020242310231023102310231020202310231310202;CP=2;R=41;
						# novy button          # MU;P0=706;P1=-763;P2=370;P3=-405;P4=-15980;D=0123012301230304230123012301230123012303042;CP=2;R=42;
						### Neff Transmitter SF01 01319004 (SF01_01319004) 433,92 MHz
						# https://github.com/RFD-FHEM/RFFHEM/issues/376
						# MU;P0=-707;P1=332;P2=-376;P3=670;P5=-15243;D=01012301232323230123012301232301010123510123012323232301230123012323010101235101230123232323012301230123230101012351012301232323230123012301232301010123510123012323232301230123012323010101235101230123232323012301230123230101012351012301232323230123012301;CP=1;R=3;O;
						# MU;P0=-32001;P1=348;P2=-704;P3=-374;P4=664;P5=-15255;D=01213421343434342134213421343421213434512134213434343421342134213434212134345121342134343434213421342134342121343451213421343434342134213421343421213434512134213434343421342134213434212134345121342134343434213421342134342121343451213421343434342134213421;CP=1;R=15;O;
						# MU;P0=-32001;P1=326;P2=-721;P3=-385;P4=656;P5=-15267;D=01213421343434342134213421343421342134512134213434343421342134213434213421345121342134343434213421342134342134213451213421343434342134213421343421342134512134213434343421342134213434213421345121342134343434213421342134342134213451213421343434342134213421;CP=1;R=10;O;
						# MU;P0=-372;P1=330;P2=684;P3=-699;P4=-14178;D=010231020202023102310231020231310231413102310202020231023102310202313102314;CP=1;R=253;
						# MU;P0=-710;P1=329;P2=-388;P3=661;P4=-14766;D=01232301410123012323232301230123012323012323014;CP=1;R=1;
						### BOSCH Transmitter SF01 01319004 (SF01_01319004_Typ2) 433,92 MHz
						# MU;P0=706;P1=-160;P2=140;P3=-335;P4=-664;P5=385;P6=-15226;P7=248;D=01210103045303045453030304545453030454530653030453030454530303045454530304747306530304530304545303030454545303045453065303045303045453030304545453030454530653030453030454530303045454530304545306530304530304545303030454545303045453065303045303045453030304;CP=5;O;
						# MU;P0=-15222;P1=379;P2=-329;P3=712;P6=-661;D=30123236123236161232323616161232361232301232361232361612323236161612323612323012323612323616123232361616123236123230123236123236161232323616161232361232301232361232361612323236161612323612323012323612323616123232361616123236123230123236123236161232323616;CP=1;O;
						# MU;P0=705;P1=-140;P2=-336;P3=-667;P4=377;P5=-15230;P6=248;D=01020342020343420202034343420202020345420203420203434202020343434202020203654202034202034342020203434342020202034542020342020343420202034343420202020345420203420203434202020343434202020203454202034202034342020203434342020202034542020342020343420202034343;CP=4;O;
						# MU;P0=704;P1=-338;P2=-670;P3=378;P4=-15227;P5=244;D=01023231010102323231010102310431010231010232310101023232310101025104310102310102323101010232323101010231043101023101023231010102323231010102310431010231010232310101023232310101023104310102310102323101010232323101010231043101023101023231010102323231010102;CP=3;O;
						# MU;P0=-334;P1=709;P2=-152;P3=-663;P4=379;P5=-15226;P6=250;D=01210134010134340101013434340101340134540101340101343401010134343401013601365401013401013434010101343434010134013454010134010134340101013434340101340134540101340101343401010134343401013401345401013401013434010101343434010134013454010134010134340101013434;CP=4;O;
		{
			name					=> 'BOSCH|CAME|Novy|Neff',
			comment				=> 'remote control CAME TOP 432EV, Novy 840029, BOSCH or Neff SF01 01319004',
			id						=> '86',
			one						=> [-2,1],
			zero					=> [-1,2],
			start					=> [-44,1],
			clockabs			=> 350,
			clockpos			=> ['one',1],
			format				=> 'twostate',
			preamble			=> 'P86#',				# prepend to converted message
			clientmodule	=> 'SD_UT',
			#modulematch	=> '^P86#.*',
			length_min		=> '12',
			length_max		=> '18',
		},
	"87"	=>	## JAROLIFT Funkwandsender TDRC 16W / TDRCT 04W
						# https://github.com/RFD-FHEM/RFFHEM/issues/380
						# MS;P1=1524;P2=-413;P3=388;P4=-3970;P5=-815;P6=778;P7=-16024;D=34353535623562626262626235626262353562623535623562626235356235626262623562626262626262626262626262623535626235623535353535626262356262626262626267123232323232323232323232;CP=3;SP=4;R=226;O;m2;
						# MS;P0=-15967;P1=1530;P2=-450;P3=368;P4=-3977;P5=-835;P6=754;D=34353562623535623562623562356262626235353562623562623562626235353562623562626262626262626262626262623535626235623535353535626262356262626262626260123232323232323232323232;CP=3;SP=4;R=229;O;
		{
			name					=> 'JAROLIFT',
			comment				=> 'remote control JAROLIFT TDRC_16W / TDRCT_04W',
			id						=> '87',
			one						=> [1,-2],
			zero					=> [2,-1],
			sync					=> [1,-10],				# this is a end marker, but we use this as a start marker
			clockabs			=> 400,						# ca 400us
			developId			=> 'y',
			format				=> 'twostate',
			preamble			=> 'u87#',				# prepend to converted message	
			#clientmodule	=> '',
			#modulematch	=> '',
			length_min		=> '72',					# 72
			length_max		=> '85',					# 85
		},
	"88"	=>	## Roto Dachfensterrolladen | Aurel Fernbedienung "TX-nM-HCS" (HCS301 Chip) | three buttons -> up, Stop, down
						# https://forum.fhem.de/index.php/topic,91244.0.html
						# MS;P1=361;P2=-435;P4=-4018;P5=-829;P6=759;P7=-16210;D=141562156215156262626215151562626215626215621562151515621562151515156262156262626215151562156215621515151515151562151515156262156215171212121212121212121212;CP=1;SP=4;R=66;O;m0;
						# MS;P0=-16052;P1=363;P2=-437;P3=-4001;P4=-829;P5=755;D=131452521452145252521452145252521414141452521452145214141414525252145252145252525214141452145214521414141414141452141414145252145252101212121212121212121212;CP=1;SP=3;R=51;O;m1;
		{
			name					=> 'Roto shutter',
			comment				=> 'remote control Aurel TX-nM-HCS',
			id						=> '88',
			one						=> [1,-2],
			zero					=> [2,-1],
			sync					=> [1,-10],				# this is a end marker, but we use this as a start marker
			clockabs			=> 400,						# ca 400us
			developId			=> 'y',
			format				=> 'twostate',
			preamble			=> 'u88#',				# prepend to converted message
			#clientmodule	=> '',
			#modulematch	=> '',
			length_min		=> '65',
			length_max		=> '78',
		},
	"89" => ## Funk Wetterstation TFA 35.1140.01 mit Temperatur-/Feuchtesensor TFA 30.3221.02 12/2018@Iron-R
					# https://github.com/RFD-FHEM/RFFHEM/issues/266
					# MU;P0=-900;P1=390;P2=-499;P3=-288;P4=193;P7=772;D=1213424213131342134242424213134242137070707013424213134242131342134242421342424213421342131342421313134213424242421313424213707070701342421313424213134213424242134242421342134213134242131313421342424242131342421;CP=4;R=43;
					# MU;P0=-491;P1=382;P2=-270;P3=179;P4=112;P5=778;P6=-878;D=01212304012123012303030123030301230123012303030121212301230301230121212121256565656123030121230301212301230303012303030123012301230303012121230123030123012121212125656565612303012123030121230123030301230303012301230123030301212123012303012301212121212565;CP=3;R=43;O;
					# MU;P0=-299;P1=384;P2=169;P3=-513;P5=761;P6=-915;D=01023232310101010101023565656561023231010232310102310232323102323231023231010232323101010102323231010101010102356565656102323101023231010231023232310232323102323101023232310101010232323101010101010235656565610232310102323101023102323231023232310232310102;CP=2;R=43;O;
					# MU;P0=-32001;P1=412;P2=-289;P3=173;P4=-529;P5=777;P6=-899;D=01234345656541212341234123434121212121234123412343412343456565656121212123434343434343412343412343434121234123412343412121212123412341234341234345656565612121212343434343434341234341234343412123412341234341212121212341234123434123434565656561212121234343;CP=3;R=22;O;
					# MU;P0=22960;P1=-893;P2=775;P3=409;P4=-296;P5=182;P6=-513;D=01212121343434345656565656565634565634565656343456563434565634343434345656565656565656342121212134343434565656565656563456563456565634345656343456563434343434565656565656565634212121213434343456565656565656345656345656563434565634345656343434343456565656;CP=5;R=22;O;
					# MU;P0=172;P1=-533;P2=401;P3=-296;P5=773;P6=-895;D=01230101230101012323010101230123010101010101230101230101012323010101230123010301230101010101012301012301010123230101012301230101010123010101010101012301565656562323232301010101010101230101230101012323010101230123010101012301010101010101230156565656232323;CP=0;R=23;O;
		{
			name         => 'TFA 30.3221.02',
			comment      => 'Temperature / humidity sensor for weatherstation TFA 35.1140.01',
			id           => '89',
			one          => [2,-1],
			zero         => [1,-2],
			start        => [3,-3,3,-3,3,-3],
			clockabs     => 250,
			clockpos     => ['zero',0],
			format       => 'twostate',
			preamble     => 'W89#',
			#postamble    => '',
			clientmodule => 'SD_WS',
			length_min   => '40',
			length_max   => '40',
		},
	"999" =>  # 
	{
		versionProtocolList  => '02.11.18'
	}
);





sub
SIGNALduino_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "SIGNALduino_Read";
  $hash->{WriteFn} = "SIGNALduino_Write";
  $hash->{ReadyFn} = "SIGNALduino_Ready";

# Normal devices
  $hash->{DefFn}  		 	= "SIGNALduino_Define";
  $hash->{FingerprintFn} 	= "SIGNALduino_FingerprintFn";
  $hash->{UndefFn} 		 	= "SIGNALduino_Undef";
  $hash->{GetFn}   			= "SIGNALduino_Get";
  $hash->{SetFn}   			= "SIGNALduino_Set";
  $hash->{AttrFn}  			= "SIGNALduino_Attr";
  $hash->{AttrList}			= 
                       "Clients MatchList do_not_notify:1,0 dummy:1,0"
					  ." hexFile"
                      ." initCommands"
                      ." flashCommand"
  					  ." hardware:nano328,uno,promini328,nanoCC1101"
					  ." debug:0,1"
					  ." longids"
					  ." minsecs"
					  ." whitelist_IDs"
					  ." blacklist_IDs"
					  ." WS09_WSModel:WH3080,WH1080,CTW600"
					  ." WS09_CRCAUS:0,1,2"
					  ." addvaltrigger"
					  ." rawmsgEvent:1,0"
					  ." cc1101_frequency"
					  ." doubleMsgCheck_IDs"
					  ." suppressDeviceRawmsg:1,0"
					  ." development"
					  ." noMsgVerbose:0,1,2,3,4,5"
					  ." maxMuMsgRepeat"
		              ." $readingFnAttributes";

  $hash->{ShutdownFn} = "SIGNALduino_Shutdown";
  
  $hash->{msIdList} = ();
  $hash->{muIdList} = ();
  $hash->{mcIdList} = ();
  
}

sub
SIGNALduino_FingerprintFn($$)
{
  my ($name, $msg) = @_;

  # Store only the "relevant" part, as the Signalduino won't compute the checksum
  #$msg = substr($msg, 8) if($msg =~ m/^81/ && length($msg) > 8);

  return ("", $msg);
}

#####################################
sub
SIGNALduino_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> SIGNALduino {none | devicename[\@baudrate] | devicename\@directio | hostname:port}";
    Log3 undef, 2, $msg;
    return $msg;
  }
  
  DevIo_CloseDev($hash);
  my $name = $a[0];

  
  if (!exists &round)
  {
      Log3 $name, 1, "$name: Signalduino can't be activated (sub round not found). Please update Fhem via update command";
	  return undef;
  }
  
  my $dev = $a[2];
  #Debug "dev: $dev" if ($debug);
  #my $hardware=AttrVal($name,"hardware","nano328");
  #Debug "hardware: $hardware" if ($debug);
 
 
  if($dev eq "none") {
    Log3 $name, 1, "$name: device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    #return undef;
  }
  

  if ($dev ne "none" && $dev =~ m/[a-zA-Z]/ && $dev !~ m/\@/) {    # bei einer IP wird kein \@57600 angehaengt
	$dev .= "\@57600";
  }	
  
  #$hash->{CMDS} = "";
  $hash->{Clients} = $clientsSIGNALduino;
  $hash->{MatchList} = \%matchListSIGNALduino;
  

  #if( !defined( $attr{$name}{hardware} ) ) {
  #  $attr{$name}{hardware} = "nano328";
  #}


  if( !defined( $attr{$name}{flashCommand} ) ) {
#    $attr{$name}{flashCommand} = "avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]"
     $attr{$name}{flashCommand} = "avrdude -c arduino -b [BAUDRATE] -P [PORT] -p atmega328p -vv -U flash:w:[HEXFILE] 2>[LOGFILE]"; 
    
  }
  $hash->{DeviceName} = $dev;
  
  my $ret=undef;
  
  InternalTimer(gettimeofday(), 'SIGNALduino_IdList',"sduino_IdList:$name",0);       # verzoegern bis alle Attribute eingelesen sind
  
  if($dev ne "none") {
    $ret = DevIo_OpenDev($hash, 0, "SIGNALduino_DoInit", 'SIGNALduino_Connect');
  } else {
		$hash->{DevState} = 'initialized';
  		readingsSingleUpdate($hash, "state", "opened", 1);
  }
  
  $hash->{DMSG}="nothing";
  $hash->{LASTDMSG} = "nothing";
  $hash->{TIME}=time();
  $hash->{versionmodul} = SDUINO_VERSION;
  if (exists($ProtocolListSIGNALduino{999}) && defined($ProtocolListSIGNALduino{999}{versionProtocolList})) {
	$hash->{versionprotoL} = $ProtocolListSIGNALduino{999}{versionProtocolList};
  }
  
  Log3 $name, 3, "$name: Firmwareversion: ".$hash->{READINGS}{version}{VAL}  if ($hash->{READINGS}{version}{VAL});

  return $ret;
}

###############################
sub SIGNALduino_Connect($$)
{
	my ($hash, $err) = @_;

	# damit wird die err-msg nur einmal ausgegeben
	if (!defined($hash->{disConnFlag}) && $err) {
		SIGNALduino_Log3($hash, 3, "$hash->{NAME}: ${err}");
		$hash->{disConnFlag} = 1;
	}
}

#####################################
sub
SIGNALduino_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  
  
 

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        SIGNALduino_Log3 $name, $lev, "$name: deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }

  SIGNALduino_Shutdown($hash);
  
  DevIo_CloseDev($hash); 
  RemoveInternalTimer($hash);    
  return undef;
}

#####################################
sub
SIGNALduino_Shutdown($)
{
  my ($hash) = @_;
  #DevIo_SimpleWrite($hash, "XQ\n",2);
  SIGNALduino_SimpleWrite($hash, "XQ");  # Switch reception off, it may hang up the SIGNALduino
  return undef;
}

#####################################
#$hash,$name,"sendmsg","P17;R6#".substr($arg,2)

sub
SIGNALduino_Set($@)
{
  my ($hash, @a) = @_;
  
  return "\"set SIGNALduino\" needs at least one parameter" if(@a < 2);

  #SIGNALduino_Log3 $hash, 3, "SIGNALduino_Set called with params @a";


  my $hasCC1101 = 0;
  my $CC1101Frequency;
  if ($hash->{version} && $hash->{version} =~ m/cc1101/) {
    $hasCC1101 = 1;
    if (!defined($hash->{cc1101_frequency})) {
       $CC1101Frequency = "433";
    } else {
       $CC1101Frequency = $hash->{cc1101_frequency};
    }
  }
  if (!defined($sets{$a[1]})) {
    my $arguments = ' ';
    foreach my $arg (sort keys %sets) {
      next if ($arg =~ m/cc1101/ && $hasCC1101 == 0);
      if ($arg =~ m/patable/) {
        next if (substr($arg, -3) ne $CC1101Frequency);
      }
      $arguments.= $arg . ($sets{$arg} ? (':' . $sets{$arg}) : '') . ' ';
    }
    #SIGNALduino_Log3 $hash, 3, "set arg = $arguments";
    return "Unknown argument $a[1], choose one of " . $arguments;
  }

  my $name = shift @a;
  my $cmd = shift @a;
  my $arg = join(" ", @a);
  
  if ($cmd =~ m/cc1101/ && $hasCC1101 == 0) {
    return "This command is only available with a cc1101 receiver";
  }
  
  return "$name is not active, may firmware is not suppoted, please flash or reset" if ($cmd ne 'reset' && $cmd ne 'flash' && exists($hash->{DevState}) && $hash->{DevState} ne 'initialized');

  if ($cmd =~ m/^cc1101_/) {
     $cmd = substr($cmd,7);
  }
  
  if($cmd eq "raw") {
    SIGNALduino_Log3 $name, 4, "set $name $cmd $arg";
    if ($arg =~ m/^Wseq /) {
       my @args = split(' ', $arg);
       foreach my $argcmd (@args) {
          if ($argcmd ne "Wseq") {
             #Log3 $name, 4, "set $name raw Wseq: $argcmd";
             SIGNALduino_AddSendQueue($hash,$argcmd);
          }
       }
    } else {
       #SIGNALduino_SimpleWrite($hash, $arg);
       SIGNALduino_AddSendQueue($hash,$arg);
    }
  } elsif( $cmd eq "flash" ) {
    my @args = split(' ', $arg);
    my $log = "";
    my $hexFile = "";
    my @deviceName = split('@', $hash->{DeviceName});
    my $port = $deviceName[0];
	my $hardware=AttrVal($name,"hardware","");
	my $baudrate=$hardware eq "uno" ? 115200 : 57600;
    my $defaultHexFile = "./FHEM/firmware/$hash->{TYPE}_$hardware.hex";
    my $logFile = AttrVal("global", "logdir", "./log/") . "$hash->{TYPE}-Flash.log";

	return "Please define your hardware! (attr $name hardware <model of your receiver>) " if ($hardware eq "");
	return "ERROR: argument failed! flash [hexFile|url]" if (!$args[0]);
	
    if(!$arg || $args[0] !~ m/^(\w|\/|.)+$/) {
      $hexFile = AttrVal($name, "hexFile", "");
      if ($hexFile eq "") {
        $hexFile = $defaultHexFile;
      }
    }
    elsif ($args[0] =~ m/^https?:\/\// ) {
		my $http_param = {
		                    url        => $args[0],
		                    timeout    => 5,
		                    hash       => $hash,                                  # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
		                    method     => "GET",                                  # Lesen von Inhalten
		                    callback   =>  \&SIGNALduino_ParseHttpResponse,        # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
		                    command    => 'flash',
		                };
		
		HttpUtils_NonblockingGet($http_param);       
		return;  	
    } else {
      $hexFile = $args[0];
    }
	SIGNALduino_Log3 $name, 3, "$name: filename $hexFile provided, trying to flash";
 
    return "Usage: set $name flash [filename]\n\nor use the hexFile attribute" if($hexFile !~ m/^(\w|\/|.)+$/);

    $log .= "flashing Arduino $name\n";
    $log .= "hex file: $hexFile\n";
    $log .= "port: $port\n";
    $log .= "log file: $logFile\n";

    my $flashCommand = AttrVal($name, "flashCommand", "");

    if($flashCommand ne "") {
      if (-e $logFile) {
        unlink $logFile;
      }

      DevIo_CloseDev($hash);
      $hash->{STATE} = "disconnected";
      $log .= "$name closed\n";

      my $avrdude = $flashCommand;
      $avrdude =~ s/\Q[PORT]\E/$port/g;
      $avrdude =~ s/\Q[BAUDRATE]\E/$baudrate/g;
      $avrdude =~ s/\Q[HEXFILE]\E/$hexFile/g;
      $avrdude =~ s/\Q[LOGFILE]\E/$logFile/g;

      $log .= "command: $avrdude\n\n";
      `$avrdude`;

      local $/=undef;
      if (-e $logFile) {
        open FILE, $logFile;
        my $logText = <FILE>;
        close FILE;
        $log .= "--- AVRDUDE ---------------------------------------------------------------------------------\n";
        $log .= $logText;
        $log .= "--- AVRDUDE ---------------------------------------------------------------------------------\n\n";
      }
      else {
        $log .= "WARNING: avrdude created no log file\n\n";
      }

    }
    else {
      $log .= "\n\nNo flashCommand found. Please define this attribute.\n\n";
    }

    DevIo_OpenDev($hash, 0, "SIGNALduino_DoInit", 'SIGNALduino_Connect');
    $log .= "$name opened\n";

    return $log;

  } elsif ($cmd =~ m/reset/i) {
	delete($hash->{initResetFlag}) if defined($hash->{initResetFlag});
	return SIGNALduino_ResetDevice($hash);
  } elsif( $cmd eq "close" ) {
	$hash->{DevState} = 'closed';
	return SIGNALduino_CloseDevice($hash);
  } elsif( $cmd eq "disableMessagetype" ) {
	my $argm = 'CD' . substr($arg,-1,1);
	#SIGNALduino_SimpleWrite($hash, $argm);
	SIGNALduino_AddSendQueue($hash,$argm);
	SIGNALduino_Log3 $name, 4, "set $name $cmd $arg $argm";;
  } elsif( $cmd eq "enableMessagetype" ) {
	my $argm = 'CE' . substr($arg,-1,1);
	#SIGNALduino_SimpleWrite($hash, $argm);
	SIGNALduino_AddSendQueue($hash,$argm);
	SIGNALduino_Log3 $name, 4, "set $name $cmd $arg $argm";
  } elsif( $cmd eq "freq" ) {
	if ($arg eq "") {
		$arg = AttrVal($name,"cc1101_frequency", 433.92);
	}
	my $f = $arg/26*65536;
	my $f2 = sprintf("%02x", $f / 65536);
	my $f1 = sprintf("%02x", int($f % 65536) / 256);
	my $f0 = sprintf("%02x", $f % 256);
	$arg = sprintf("%.3f", (hex($f2)*65536+hex($f1)*256+hex($f0))/65536*26);
	SIGNALduino_Log3 $name, 3, "$name: Setting FREQ2..0 (0D,0E,0F) to $f2 $f1 $f0 = $arg MHz";
	SIGNALduino_AddSendQueue($hash,"W0F$f2");
	SIGNALduino_AddSendQueue($hash,"W10$f1");
	SIGNALduino_AddSendQueue($hash,"W11$f0");
	SIGNALduino_WriteInit($hash);
  } elsif( $cmd eq "bWidth" ) {
	SIGNALduino_AddSendQueue($hash,"C10");
	$hash->{getcmd}->{cmd} = "bWidth";
	$hash->{getcmd}->{arg} = $arg;
  } elsif( $cmd eq "rAmpl" ) {
	return "a numerical value between 24 and 42 is expected" if($arg !~ m/^\d+$/ || $arg < 24 || $arg > 42);
	my ($v, $w);
	for($v = 0; $v < @ampllist; $v++) {
		last if($ampllist[$v] > $arg);
	}
	$v = sprintf("%02d", $v-1);
	$w = $ampllist[$v];
	SIGNALduino_Log3 $name, 3, "$name: Setting AGCCTRL2 (1B) to $v / $w dB";
	SIGNALduino_AddSendQueue($hash,"W1D$v");
	SIGNALduino_WriteInit($hash);
  } elsif( $cmd eq "sens" ) {
	return "a numerical value between 4 and 16 is expected" if($arg !~ m/^\d+$/ || $arg < 4 || $arg > 16);
	my $w = int($arg/4)*4;
	my $v = sprintf("9%d",$arg/4-1);
	SIGNALduino_Log3 $name, 3, "$name: Setting AGCCTRL0 (1D) to $v / $w dB";
	SIGNALduino_AddSendQueue($hash,"W1F$v");
	SIGNALduino_WriteInit($hash);
  } elsif( substr($cmd,0,7) eq "patable" ) {
	my $paFreq = substr($cmd,8);
	my $pa = "x" . $patable{$paFreq}{$arg};
	SIGNALduino_Log3 $name, 3, "$name: Setting patable $paFreq $arg $pa";
	SIGNALduino_AddSendQueue($hash,$pa);
	SIGNALduino_WriteInit($hash);
  } elsif( $cmd eq "sendMsg" ) {
	SIGNALduino_Log3 $name, 5, "$name: sendmsg msg=$arg";
	
	# Split args in serval variables
	my ($protocol,$data,$repeats,$clock,$frequency,$datalength,$dataishex);
	my $n=0;
	foreach my $s (split "#", $arg) {
	    my $c = substr($s,0,1);
	    if ($n == 0 ) {  #  protocol
			$protocol = substr($s,1);
	    } elsif ($n == 1) { # Data
	        $data = $s;
	        if   ( substr($s,0,2) eq "0x" ) { $dataishex=1; $data=substr($data,2); }
	        else { $dataishex=0; }
	        
	    } else {
	    	    if ($c eq 'R') { $repeats = substr($s,1);  }
	    		elsif ($c eq 'C') { $clock = substr($s,1);   }
	    		elsif ($c eq 'F') { $frequency = substr($s,1);  }
	    		elsif ($c eq 'L') { $datalength = substr($s,1);   }
	    }
	    $n++;
	}
	return "$name: sendmsg, unknown protocol: $protocol" if (!exists($ProtocolListSIGNALduino{$protocol}));

	$repeats=1 if (!defined($repeats));

	if (exists($ProtocolListSIGNALduino{$protocol}{frequency}) && $hasCC1101 && !defined($frequency)) {
		$frequency = $ProtocolListSIGNALduino{$protocol}{frequency};
	}
	if (defined($frequency) && $hasCC1101) {
		$frequency="F=$frequency;";
	} else {
		$frequency="";
	}
	
	#print ("data = $data \n");
	#print ("protocol = $protocol \n");
    #print ("repeats = $repeats \n");
    
	my %signalHash;
	my %patternHash;
	my $pattern="";
	my $cnt=0;
	
	my $sendData;
	if  ($ProtocolListSIGNALduino{$protocol}{format} eq 'manchester')
	{
		#$clock = (map { $clock += $_ } @{$ProtocolListSIGNALduino{$protocol}{clockrange}}) /  2 if (!defined($clock));
		
		$clock += $_ for(@{$ProtocolListSIGNALduino{$protocol}{clockrange}});
		$clock = round($clock/2,0);
		if ($protocol == 43) {
			#$data =~ tr/0123456789ABCDEF/FEDCBA9876543210/;
		}
		
		my $intro = "";
		my $outro = "";
		
		$intro = $ProtocolListSIGNALduino{$protocol}{msgIntro} if ($ProtocolListSIGNALduino{$protocol}{msgIntro});
		$outro = $ProtocolListSIGNALduino{$protocol}{msgOutro}.";" if ($ProtocolListSIGNALduino{$protocol}{msgOutro});

		if ($intro ne "" || $outro ne "")
		{
			$intro = "SC;R=$repeats;" . $intro;
			$repeats = 0;
		}

		$sendData = $intro . "SM;" . ($repeats > 0 ? "R=$repeats;" : "") . "C=$clock;D=$data;" . $outro . $frequency; #	SM;R=2;C=400;D=AFAFAF;
		SIGNALduino_Log3 $name, 5, "$name: sendmsg Preparing manchester protocol=$protocol, repeats=$repeats, clock=$clock data=$data";
	} else {
		if ($protocol == 3 || substr($data,0,2) eq "is") {
			if (substr($data,0,2) eq "is") {
				$data = substr($data,2);   # is am Anfang entfernen
			}
			if ($protocol == 3) {
				$data = SIGNALduino_ITV1_tristateToBit($data);
			} else {
				$data = SIGNALduino_ITV1_31_tristateToBit($data);	# $protocolId 3.1
			}
			SIGNALduino_Log3 $name, 5, "$name: sendmsg IT V1 convertet tristate to bits=$data";
		}
		if (!defined($clock)) {
			$hash->{ITClock} = 250 if (!defined($hash->{ITClock}));   # Todo: Klaeren wo ITClock verwendet wird und ob wir diesen Teil nicht auf Protokoll 3,4 und 17 minimieren
			$clock=$ProtocolListSIGNALduino{$protocol}{clockabs} > 1 ?$ProtocolListSIGNALduino{$protocol}{clockabs}:$hash->{ITClock};
		}
		
		if ($dataishex == 1)	
		{
			# convert hex to bits
	        my $hlen = length($data);
	        my $blen = $hlen * 4;
	        $data = unpack("B$blen", pack("H$hlen", $data));
		}

		SIGNALduino_Log3 $name, 5, "$name: sendmsg Preparing rawsend command for protocol=$protocol, repeats=$repeats, clock=$clock bits=$data";
		
		foreach my $item (qw(sync start one zero float pause end))
		{
		    #print ("item= $item \n");
		    next if (!exists($ProtocolListSIGNALduino{$protocol}{$item}));
		    
			foreach my $p (@{$ProtocolListSIGNALduino{$protocol}{$item}})
			{
			    #print (" p = $p \n");
			    
			    if (!exists($patternHash{$p}))
				{
					$patternHash{$p}=$cnt;
					$pattern.="P".$patternHash{$p}."=".$p*$clock.";";
					$cnt++;
				}
		    	$signalHash{$item}.=$patternHash{$p};
			   	#print (" signalHash{$item} = $signalHash{$item} \n");
			}
		}
		my @bits = split("", $data);
	
		my %bitconv = (1=>"one", 0=>"zero", 'D'=> "float", 'F'=> "float", 'P'=> "pause");
		my $SignalData="D=";
		
		$SignalData.=$signalHash{sync} if (exists($signalHash{sync}));
		$SignalData.=$signalHash{start} if (exists($signalHash{start}));
		foreach my $bit (@bits)
		{
			next if (!exists($bitconv{$bit}));
			#SIGNALduino_Log3 $name, 5, "encoding $bit";
			$SignalData.=$signalHash{$bitconv{$bit}}; ## Add the signal to our data string
		}
		$SignalData.=$signalHash{end} if (exists($signalHash{end}));
		$sendData = "SR;R=$repeats;$pattern$SignalData;$frequency";
	}

	
	#SIGNALduino_SimpleWrite($hash, $sendData);
	SIGNALduino_AddSendQueue($hash,$sendData);
	SIGNALduino_Log3 $name, 4, "$name/set: sending via SendMsg: $sendData";
  } else {
  	SIGNALduino_Log3 $name, 5, "$name/set: set $name $cmd $arg";
	#SIGNALduino_SimpleWrite($hash, $arg);
	return "Unknown argument $cmd, choose one of ". ReadingsVal($name,'cmd',' help me');
  }

  return undef;
}

#####################################
sub
SIGNALduino_Get($@)
{
  my ($hash, @a) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};
  return "$name is not active, may firmware is not suppoted, please flash or reset" if (exists($hash->{DevState}) && $hash->{DevState} ne 'initialized');
  #my $name = $a[0];
  
  SIGNALduino_Log3 $name, 5, "\"get $type\" needs at least one parameter" if(@a < 2);
  return "\"get $type\" needs at least one parameter" if(@a < 2);
  if(!defined($gets{$a[1]})) {
    my @cList = map { $_ =~ m/^(file|raw|ccreg)$/ ? $_ : "$_:noArg" } sort keys %gets;
    return "Unknown argument $a[1], choose one of " . join(" ", @cList);
  }

  my $arg = ($a[2] ? $a[2] : "");
  return "no command to send, get aborted." if (length($gets{$a[1]}[0]) == 0 && length($arg) == 0);
  
  if (($a[1] eq "ccconf" || $a[1] eq "ccreg" || $a[1] eq "ccpatable") && $hash->{version} && $hash->{version} !~ m/cc1101/) {
    return "This command is only available with a cc1101 receiver";
  }
  
  my ($msg, $err);

  if (IsDummy($name))
  {
  	if ($arg =~ /^M[CcSU];.*/)
  	{
		$arg="\002$arg\003";  	## Add start end end marker if not already there
		SIGNALduino_Log3 $name, 5, "$name/msg adding start and endmarker to message";
	
	}
	if ($arg =~ /\002M.;.*;\003$/)
	{
		SIGNALduino_Log3 $name, 4, "$name/msg get raw: $arg";
		return SIGNALduino_Parse($hash, $hash, $hash->{NAME}, $arg);
  	}
  	else {
		my $arg2 = "";
		if ($arg =~ m/^version=/) {           # set version
			$arg2 = substr($arg,8);
			$hash->{version} = "V " . $arg2;
		}
		elsif ($arg =~ m/^regexp=/) {         # set fileRegexp for get raw messages from file
			$arg2 = substr($arg,7);
			$hash->{fileRegexp} = $arg2;
			delete($hash->{fileRegexp}) if (!$arg2);
		}
		elsif ($arg =~ m/^file=/) {
			$arg2 = substr($arg,5);
			my $n = 0;
			if (open(my $fh, '<', $arg2)) {
				my $fileRegexp = $hash->{fileRegexp};
				while (my $row = <$fh>) {
					if ($row =~ /.*\002M.;.*;\003$/) {
						chomp $row;
						$row =~ s/.*\002(M.;.*;)\003/$1/;
						if (!defined($fileRegexp) || $row =~ m/$fileRegexp/) {
							$n += 1;
							$row="\002$row\003";
							SIGNALduino_Log3 $name, 4, "$name/msg fileGetRaw: $row";
							SIGNALduino_Parse($hash, $hash, $hash->{NAME}, $row);
						}
					}
				}
				return $n . " raw Nachrichten eingelesen";
			} else {
				return "Could not open file $arg2";
			}
		}
		elsif ($arg eq '?') {
			my $ret;
			
			$ret = "dummy get raw\n\n";
			$ret .= "raw message       e.g. MS;P0=-392;P1=...\n";
			$ret .= "dispatch message  e.g. P7#6290DCF37\n";
			$ret .= "version=x.x.x     sets version. e.g. (version=3.2.0) to get old MC messages\n";
			$ret .= "regexp=           set fileRegexp for get raw messages from file. e.g. regexp=^MC\n";
			$ret .= "file=             gets raw messages from file in the fhem directory\n";
			return $ret;
		}
		else {
			SIGNALduino_Log3 $name, 4, "$name/msg get dispatch: $arg";
			Dispatch($hash, $arg, undef);
		}
		return "";
  	}
  }
  return "No $a[1] for dummies" if(IsDummy($name));

  SIGNALduino_Log3 $name, 5, "$name: command for gets: " . $gets{$a[1]}[0] . " " . $arg;

  if ($a[1] eq "raw")
  {
  	# Dirty hack to check and modify direct communication from logical modules with hardware
  	if ($arg =~ /^is.*/ && length($arg) == 34)
  	{
  		# Arctec protocol
  		SIGNALduino_Log3 $name, 5, "$name: calling set :sendmsg P17;R6#".substr($arg,2);
  		
  		SIGNALduino_Set($hash,$name,"sendMsg","P17#",substr($arg,2),"#R6");
  	    return "$a[0] $a[1] => $arg";
  	}
  	
  }
  elsif ($a[1] eq "protocolIDs")
  {
	my $id;
	my $ret;
	my $s;
	my $moduleId;
	my @IdList = ();
	
	foreach $id (keys %ProtocolListSIGNALduino)
	{
		next if ($id eq 'id');
		push (@IdList, $id);
	}
	@IdList = sort { $a <=> $b } @IdList;
	
	$ret = " ID    modulname       protocolname # comment\n\n";
	
	foreach $id (@IdList)
	{
		next if ($id > 900);
		
		$ret .= sprintf("%3s",$id) . " ";
		
		if (exists ($ProtocolListSIGNALduino{$id}{format}) && $ProtocolListSIGNALduino{$id}{format} eq "manchester")
		{
			$ret .= "MC";
		}
		elsif (exists $ProtocolListSIGNALduino{$id}{sync})
		{
			$ret .= "MS";
		}
		elsif (exists ($ProtocolListSIGNALduino{$id}{clockabs}))
		{
			$ret .= "MU";
		}
		
		if (exists ($ProtocolListSIGNALduino{$id}{clientmodule}))
		{
			$moduleId .= "$id,";
			$s = $ProtocolListSIGNALduino{$id}{clientmodule};
			if (length($s) < 15)
			{
				$s .= substr("               ",length($s) - 15);
			}
			$ret .= " $s";
		}
		else
		{
			$ret .= "                ";
		}
		
		if (exists ($ProtocolListSIGNALduino{$id}{name}))
		{
			$ret .= " $ProtocolListSIGNALduino{$id}{name}";
		}
		
		if (exists ($ProtocolListSIGNALduino{$id}{comment}))
		{
			$ret .= " # $ProtocolListSIGNALduino{$id}{comment}";
		}
		
		$ret .= "\n";
	}
	#$moduleId =~ s/,$//;
	
	return "$a[1]: \n\n$ret\n";
	#return "$a[1]: \n\n$ret\nIds with modules: $moduleId";
  }
  
  #SIGNALduino_SimpleWrite($hash, $gets{$a[1]}[0] . $arg);
  SIGNALduino_AddSendQueue($hash, $gets{$a[1]}[0] . $arg);
  $hash->{getcmd}->{cmd}=$a[1];
  $hash->{getcmd}->{asyncOut}=$hash->{CL};
  $hash->{getcmd}->{timenow}=time();
  
  return undef; # We will exit here, and give an output only, if asny output is supported. If this is not supported, only the readings are updated
}

sub SIGNALduino_parseResponse($$$)
{
	my $hash = shift;
	my $cmd = shift;
	my $msg = shift;

	my $name=$hash->{NAME};
	
  	$msg =~ s/[\r\n]//g;

	if($cmd eq "cmds") 
	{       # nice it up
	    $msg =~ s/$name cmds =>//g;
   		$msg =~ s/.*Use one of//g;
 	} 
 	elsif($cmd eq "uptime") 
 	{   # decode it
   		#$msg = hex($msg);              # /125; only for col or coc
    	$msg = sprintf("%d %02d:%02d:%02d", $msg/86400, ($msg%86400)/3600, ($msg%3600)/60, $msg%60);
  	}
  	elsif($cmd eq "ccregAll")
  	{
		$msg =~ s/  /\n/g;
		$msg = "\n\n" . $msg
  	}
  	elsif($cmd eq "ccconf")
  	{
		my (undef,$str) = split('=', $msg);
		my $var;
		my %r = ( "0D"=>1,"0E"=>1,"0F"=>1,"10"=>1,"11"=>1,"1B"=>1,"1D"=>1 );
		$msg = "";
		foreach my $a (sort keys %r) {
			$var = substr($str,(hex($a)-13)*2, 2);
			$r{$a} = hex($var);
		}
		$msg = sprintf("freq:%.3fMHz bWidth:%dKHz rAmpl:%ddB sens:%ddB  (DataRate:%.2fBaud)",
		26*(($r{"0D"}*256+$r{"0E"})*256+$r{"0F"})/65536,                #Freq
		26000/(8 * (4+(($r{"10"}>>4)&3)) * (1 << (($r{"10"}>>6)&3))),   #Bw
		$ampllist[$r{"1B"}&7],                                          #rAmpl
		4+4*($r{"1D"}&3),                                               #Sens
		((256+$r{"11"})*(2**($r{"10"} & 15 )))*26000000/(2**28)         #DataRate
		);
	}
	elsif($cmd eq "bWidth") {
		my $val = hex(substr($msg,6));
		my $arg = $hash->{getcmd}->{arg};
		my $ob = $val & 0x0f;
		
		my ($bits, $bw) = (0,0);
		OUTERLOOP:
		for (my $e = 0; $e < 4; $e++) {
			for (my $m = 0; $m < 4; $m++) {
				$bits = ($e<<6)+($m<<4);
				$bw  = int(26000/(8 * (4+$m) * (1 << $e))); # KHz
				last OUTERLOOP if($arg >= $bw);
			}
		}

		$ob = sprintf("%02x", $ob+$bits);
		$msg = "Setting MDMCFG4 (10) to $ob = $bw KHz";
		SIGNALduino_Log3 $name, 3, "$name/msg parseResponse bWidth: Setting MDMCFG4 (10) to $ob = $bw KHz";
		delete($hash->{getcmd});
		SIGNALduino_AddSendQueue($hash,"W12$ob");
		SIGNALduino_WriteInit($hash);
	}
	elsif($cmd eq "ccpatable") {
		my $CC1101Frequency = "433";
		if (defined($hash->{cc1101_frequency})) {
			$CC1101Frequency = $hash->{cc1101_frequency};
		}
		my $dBn = substr($msg,9,2);
		SIGNALduino_Log3 $name, 3, "$name/msg parseResponse patable: $dBn";
		foreach my $dB (keys %{ $patable{$CC1101Frequency} }) {
			if ($dBn eq $patable{$CC1101Frequency}{$dB}) {
				SIGNALduino_Log3 $name, 5, "$name/msg parseResponse patable: $dB";
				$msg .= " => $dB";
				last;
			}
		}
	#	$msg .=  "\n\n$CC1101Frequency MHz\n\n";
	#	foreach my $dB (keys $patable{$CC1101Frequency})
	#	{
	#		$msg .= "$patable{$CC1101Frequency}{$dB}  $dB\n";
	#	}
	}
	
  	return $msg;
}


#####################################
sub
SIGNALduino_ResetDevice($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  SIGNALduino_Log3 $name, 3, "$name reset"; 
  DevIo_CloseDev($hash);
  my $ret = DevIo_OpenDev($hash, 0, "SIGNALduino_DoInit", 'SIGNALduino_Connect');

  return $ret;
}

#####################################
sub
SIGNALduino_CloseDevice($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	SIGNALduino_Log3 $name, 2, "$name closed"; 
	RemoveInternalTimer($hash);
	DevIo_CloseDev($hash);
	readingsSingleUpdate($hash, "state", "closed", 1);
	
	return undef;
}

#####################################
sub
SIGNALduino_DoInit($)
{
	my $hash = shift;
	my $name = $hash->{NAME};
	my $err;
	my $msg = undef;

	my ($ver, $try) = ("", 0);
	#Dirty hack to allow initialisation of DirectIO Device for some debugging and tesing
  	SIGNALduino_Log3 $name, 1, "$name/define: ".$hash->{DEF};
  
	delete($hash->{disConnFlag}) if defined($hash->{disConnFlag});
	RemoveInternalTimer("HandleWriteQueue:$name");
    @{$hash->{QUEUE}} = ();
    $hash->{sendworking} = 0;
    
 if (($hash->{DEF} !~ m/\@directio/) and ($hash->{DEF} !~ m/none/) )
	{
		SIGNALduino_Log3 $name, 1, "$name/init: ".$hash->{DEF};
		$hash->{initretry} = 0;
		RemoveInternalTimer($hash);
		
		#SIGNALduino_SimpleWrite($hash, "XQ"); # Disable receiver
		InternalTimer(gettimeofday() + SDUINO_INIT_WAIT_XQ, "SIGNALduino_SimpleWrite_XQ", $hash, 0);
		
		InternalTimer(gettimeofday() + SDUINO_INIT_WAIT, "SIGNALduino_StartInit", $hash, 0);
	}
	# Reset the counter
	delete($hash->{XMIT_TIME});
	delete($hash->{NR_CMD_LAST_H});
	return;
	return undef;
}

# Disable receiver
sub SIGNALduino_SimpleWrite_XQ($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	SIGNALduino_Log3 $name, 3, "$name/init: disable receiver (XQ)";
	SIGNALduino_SimpleWrite($hash, "XQ");
	#DevIo_SimpleWrite($hash, "XQ\n",2);
}


sub SIGNALduino_StartInit($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	$hash->{version} = undef;
	
	SIGNALduino_Log3 $name,3 , "$name/init: get version, retry = " . $hash->{initretry};
	if ($hash->{initretry} >= SDUINO_INIT_MAXRETRY) {
		$hash->{DevState} = 'INACTIVE';
		# einmaliger reset, wenn danach immer noch 'init retry count reached', dann SIGNALduino_CloseDevice()
		if (!defined($hash->{initResetFlag})) {
			SIGNALduino_Log3 $name,2 , "$name/init retry count reached. Reset";
			$hash->{initResetFlag} = 1;
			SIGNALduino_ResetDevice($hash);
		} else {
			SIGNALduino_Log3 $name,2 , "$name/init retry count reached. Closed";
			SIGNALduino_CloseDevice($hash);
		}
		return;
	}
	else {
		$hash->{getcmd}->{cmd} = "version";
		SIGNALduino_SimpleWrite($hash, "V");
		#DevIo_SimpleWrite($hash, "V\n",2);
		$hash->{DevState} = 'waitInit';
		RemoveInternalTimer($hash);
		InternalTimer(gettimeofday() + SDUINO_CMD_TIMEOUT, "SIGNALduino_CheckCmdResp", $hash, 0);
	}
}


####################
sub SIGNALduino_CheckCmdResp($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $msg = undef;
	my $ver;
	
	if ($hash->{version}) {
		$ver = $hash->{version};
		if ($ver !~ m/SIGNAL(duino|ESP)/) {
			$msg = "$name: Not an SIGNALduino device, setting attribute dummy=1 got for V:  $ver";
			SIGNALduino_Log3 $name, 1, $msg;
			readingsSingleUpdate($hash, "state", "no SIGNALduino found", 1);
			$hash->{DevState} = 'INACTIVE';
			SIGNALduino_CloseDevice($hash);
		}
		elsif($ver =~ m/^V 3\.1\./) {
			$msg = "$name: Version of your arduino is not compatible, pleas flash new firmware. (device closed) Got for V:  $ver";
			readingsSingleUpdate($hash, "state", "unsupported firmware found", 1);
			SIGNALduino_Log3 $name, 1, $msg;
			$hash->{DevState} = 'INACTIVE';
			SIGNALduino_CloseDevice($hash);
		}
		else {
			readingsSingleUpdate($hash, "state", "opened", 1);
			SIGNALduino_Log3 $name, 2, "$name: initialized. " . SDUINO_VERSION;
			$hash->{DevState} = 'initialized';
			delete($hash->{initResetFlag}) if defined($hash->{initResetFlag});
			SIGNALduino_SimpleWrite($hash, "XE"); # Enable receiver
			#DevIo_SimpleWrite($hash, "XE\n",2);
			SIGNALduino_Log3 $name, 3, "$name/init: enable receiver (XE)";
			delete($hash->{initretry});
			# initialize keepalive
			$hash->{keepalive}{ok}    = 0;
			$hash->{keepalive}{retry} = 0;
			InternalTimer(gettimeofday() + SDUINO_KEEPALIVE_TIMEOUT, "SIGNALduino_KeepAlive", $hash, 0);
		}
	}
	else {
		delete($hash->{getcmd});
		$hash->{initretry} ++;
		#InternalTimer(gettimeofday()+1, "SIGNALduino_StartInit", $hash, 0);
		SIGNALduino_StartInit($hash);
	}
}


#####################################
# Check if the 1% limit is reached and trigger notifies
sub
SIGNALduino_XmitLimitCheck($$)
{
  my ($hash,$fn) = @_;
 
 
  return if ($fn !~ m/^(is|SR).*/);

  my $now = time();


  if(!$hash->{XMIT_TIME}) {
    $hash->{XMIT_TIME}[0] = $now;
    $hash->{NR_CMD_LAST_H} = 1;
    return;
  }

  my $nowM1h = $now-3600;
  my @b = grep { $_ > $nowM1h } @{$hash->{XMIT_TIME}};

  if(@b > 163) {          # Maximum nr of transmissions per hour (unconfirmed).

    my $name = $hash->{NAME};
    SIGNALduino_Log3 $name, 2, "SIGNALduino TRANSMIT LIMIT EXCEEDED";
    DoTrigger($name, "TRANSMIT LIMIT EXCEEDED");

  } else {

    push(@b, $now);

  }
  $hash->{XMIT_TIME} = \@b;
  $hash->{NR_CMD_LAST_H} = int(@b);
}

#####################################
## API to logical modules: Provide as Hash of IO Device, type of function ; command to call ; message to send
sub
SIGNALduino_Write($$$)
{
  my ($hash,$fn,$msg) = @_;
  my $name = $hash->{NAME};

  if ($fn eq "") {
    $fn="RAW" ;
  }
  elsif($fn eq "04" && substr($msg,0,6) eq "010101") {   # FS20
    $fn="sendMsg";
    $msg = substr($msg,6);
    $msg = SIGNALduino_PreparingSend_FS20_FHT(74, 6, $msg);
  }
  elsif($fn eq "04" && substr($msg,0,6) eq "020183") {   # FHT
    $fn="sendMsg";
    $msg = substr($msg,6,6) . "00" . substr($msg,12); # insert Byte 3 always 0x00
    $msg = SIGNALduino_PreparingSend_FS20_FHT(73, 12, $msg);
  }
  SIGNALduino_Log3 $name, 5, "$name/write: sending via Set $fn $msg";
  
  SIGNALduino_Set($hash,$name,$fn,$msg);
}


sub SIGNALduino_AddSendQueue($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  
  push(@{$hash->{QUEUE}}, $msg);
  
  #SIGNALduino_Log3 $hash , 5, Dumper($hash->{QUEUE});
  
  SIGNALduino_Log3 $name, 5,"AddSendQueue: " . $name . ": $msg (" . @{$hash->{QUEUE}} . ")";
  InternalTimer(gettimeofday() + 0.1, "SIGNALduino_HandleWriteQueue", "HandleWriteQueue:$name") if (@{$hash->{QUEUE}} == 1 && $hash->{sendworking} == 0);
}


sub
SIGNALduino_SendFromQueue($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  
  if($msg ne "") {
	SIGNALduino_XmitLimitCheck($hash,$msg);
    #DevIo_SimpleWrite($hash, $msg . "\n", 2);
    $hash->{sendworking} = 1;
    SIGNALduino_SimpleWrite($hash,$msg);
    if ($msg =~ m/^S(R|C|M);/) {
       $hash->{getcmd}->{cmd} = 'sendraw';
       SIGNALduino_Log3 $name, 4, "$name SendrawFromQueue: msg=$msg"; # zu testen der Queue, kann wenn es funktioniert auskommentiert werden
    } 
    elsif ($msg eq "C99") {
       $hash->{getcmd}->{cmd} = 'ccregAll';
    }
  }

  ##############
  # Write the next buffer not earlier than 0.23 seconds
  # else it will be sent too early by the SIGNALduino, resulting in a collision, or may the last command is not finished
  
  if (defined($hash->{getcmd}->{cmd}) && $hash->{getcmd}->{cmd} eq 'sendraw') {
     InternalTimer(gettimeofday() + SDUINO_WRITEQUEUE_TIMEOUT, "SIGNALduino_HandleWriteQueue", "HandleWriteQueue:$name");
  } else {
     InternalTimer(gettimeofday() + SDUINO_WRITEQUEUE_NEXT, "SIGNALduino_HandleWriteQueue", "HandleWriteQueue:$name");
  }
}

####################################
sub
SIGNALduino_HandleWriteQueue($)
{
  my($param) = @_;
  my(undef,$name) = split(':', $param);
  my $hash = $defs{$name};
  
  #my @arr = @{$hash->{QUEUE}};
  
  $hash->{sendworking} = 0;       # es wurde gesendet
  
  if (defined($hash->{getcmd}->{cmd}) && $hash->{getcmd}->{cmd} eq 'sendraw') {
    SIGNALduino_Log3 $name, 4, "$name/HandleWriteQueue: sendraw no answer (timeout)";
    delete($hash->{getcmd});
  }
	  
  if(@{$hash->{QUEUE}}) {
    my $msg= shift(@{$hash->{QUEUE}});

    if($msg eq "") {
      SIGNALduino_HandleWriteQueue("x:$name");
    } else {
      SIGNALduino_SendFromQueue($hash, $msg);
    }
  } else {
  	 SIGNALduino_Log3 $name, 4, "$name/HandleWriteQueue: nothing to send, stopping timer";
  	 RemoveInternalTimer("HandleWriteQueue:$name");
  }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
SIGNALduino_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};
  my $debug = AttrVal($name,"debug",0);

  my $SIGNALduinodata = $hash->{PARTIAL};
  Log3 $name, 5, "$name/RAW READ: $SIGNALduinodata/$buf" if ($debug); 
  $SIGNALduinodata .= $buf;

  while($SIGNALduinodata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$SIGNALduinodata) = split("\n", $SIGNALduinodata, 2);
    $rmsg =~ s/\r//;
    
    	if ($rmsg =~ m/^\002(M(s|u);.*;)\003/) {
		$rmsg =~ s/^\002//;                # \002 am Anfang entfernen
		my @msg_parts = split(";",$rmsg);
		my $m0;
		my $mnr0;
		my $m1;
		my $mL;
		my $mH;
		my $part = "";
		my $partD;
		my $dOverfl = 0;
		
		foreach my $msgPart (@msg_parts) {
			next if ($msgPart eq "");
			$m0 = substr($msgPart,0,1);
			$mnr0 = ord($m0);
			$m1 = substr($msgPart,1);
			if ($m0 eq "M") {
				$part .= "M" . uc($m1) . ";";
			}
			elsif ($mnr0 > 127) {
				$part .= "P" . sprintf("%u", ($mnr0 & 7)) . "=";
				if (length($m1) == 2) {
					$mL = ord(substr($m1,0,1)) & 127;        # Pattern low
					$mH = ord(substr($m1,1,1)) & 127;        # Pattern high
					if (($mnr0 & 0b00100000) != 0) {           # Vorzeichen  0b00100000 = 32
						$part .= "-";
					}
					if ($mnr0 & 0b00010000) {                # Bit 7 von Pattern low
						$mL += 128;
					}
					$part .= ($mH * 256) + $mL;
				}
				$part .= ";";
			}
			elsif (($m0 eq "D" || $m0 eq "d") && length($m1) > 0) {
				my @arrayD = split(//, $m1);
				if ($dOverfl == 0) {
					$part .= "D=";
				}
				else {
					$part =~ s/;$//;	# ; am Ende entfernen
				}
				$dOverfl++;
				$partD = "";
				foreach my $D (@arrayD) {
					$mH = ord($D) >> 4;
					$mL = ord($D) & 7;
					$partD .= "$mH$mL";
				}
				#SIGNALduino_Log3 $name, 3, "$name/msg READredu1$m0: $partD";
				if ($m0 eq "d") {
					#SIGNALduino_Log3 $name, 4, "$name/msg ##READredu## $m0=$partD";
					$partD =~ s/.$//;	   # letzte Ziffer entfernen wenn Anzahl der Ziffern ungerade
				}
				$partD =~ s/^8//;	           # 8 am Anfang entfernen
				#SIGNALduino_Log3 $name, 3, "$name/msg READredu2$m0: $partD";
				$part = $part . $partD . ';';
			}
			elsif (($m0 eq "C" || $m0 eq "S") && length($m1) == 1) {
				$part .= "$m0" . "P=$m1;";
			}
			elsif ($m0 eq "o" || $m0 eq "m") {
				$part .= "$m0$m1;";
			}
			elsif ($m0 eq "F") {
				my $F = hex($m1);
				SIGNALduino_Log3 $name, AttrVal($name,"noMsgVerbose",4), "$name/msg READredu(o$dOverfl) FIFO=$F";
			}
			elsif ($m1 =~ m/^[0-9A-Z]{1,2}$/) {        # bei 1 oder 2 Hex Ziffern nach Dez wandeln 
				$part .= "$m0=" . hex($m1) . ";";
			}
			elsif ($m0 =~m/[0-9a-zA-Z]/) {
				$part .= "$m0";
				if ($m1 ne "") {
					$part .= "=$m1";
				}
				$part .= ";";
			}
		}
		my $MuOverfl = "";
		if ($dOverfl > 1) {
			$dOverfl--;
			$MuOverfl = "(o$dOverfl)";
		}
		Log3 $name, 4, "$name/msg READredu$MuOverfl: $part";
		$rmsg = "\002$part\003";
	}
	else {
		Log3 $name, 4, "$name/msg READ: $rmsg";
	}

	if ( $rmsg && !SIGNALduino_Parse($hash, $hash, $name, $rmsg) && defined($hash->{getcmd}) && defined($hash->{getcmd}->{cmd}))
	{
		my $regexp;
		if ($hash->{getcmd}->{cmd} eq 'sendraw') {
			$regexp = '^S(R|C|M);';
		}
		elsif ($hash->{getcmd}->{cmd} eq 'ccregAll') {
			$regexp = '^ccreg 00:';
		}
		elsif ($hash->{getcmd}->{cmd} eq 'bWidth') {
			$regexp = '^C.* = .*';
		}
		else {
			$regexp = $gets{$hash->{getcmd}->{cmd}}[1];
		}
		if(!defined($regexp) || $rmsg =~ m/$regexp/) {
			if (defined($hash->{keepalive})) {
				$hash->{keepalive}{ok}    = 1;
				$hash->{keepalive}{retry} = 0;
			}
			SIGNALduino_Log3 $name, 5, "$name/msg READ: regexp=$regexp cmd=$hash->{getcmd}->{cmd} msg=$rmsg";
			
			if ($hash->{getcmd}->{cmd} eq 'version') {
				my $msg_start = index($rmsg, 'V 3.');
				if ($msg_start > 0) {
					$rmsg = substr($rmsg, $msg_start);
					SIGNALduino_Log3 $name, 4, "$name/read: cut chars at begin. msgstart = $msg_start msg = $rmsg";
				}
				$hash->{version} = $rmsg;
				if (defined($hash->{DevState}) && $hash->{DevState} eq 'waitInit') {
					RemoveInternalTimer($hash);
					SIGNALduino_CheckCmdResp($hash);
				}
			}
			if ($hash->{getcmd}->{cmd} eq 'sendraw') {
				# zu testen der sendeQueue, kann wenn es funktioniert auf verbose 5
				SIGNALduino_Log3 $name, 4, "$name/read sendraw answer: $rmsg";
				delete($hash->{getcmd});
				RemoveInternalTimer("HandleWriteQueue:$name");
				SIGNALduino_HandleWriteQueue("x:$name");
			}
			else {
				$rmsg = SIGNALduino_parseResponse($hash,$hash->{getcmd}->{cmd},$rmsg);
				if (defined($hash->{getcmd}) && $hash->{getcmd}->{cmd} ne 'ccregAll') {
					readingsSingleUpdate($hash, $hash->{getcmd}->{cmd}, $rmsg, 0);
				}
				if (defined($hash->{getcmd}->{asyncOut})) {
					#SIGNALduino_Log3 $name, 4, "$name/msg READ: asyncOutput";
					my $ao = asyncOutput( $hash->{getcmd}->{asyncOut}, $hash->{getcmd}->{cmd}.": " . $rmsg );
				}
				delete($hash->{getcmd});
			}
		} else {
			SIGNALduino_Log3 $name, 4, "$name/msg READ: Received answer ($rmsg) for ". $hash->{getcmd}->{cmd}." does not match $regexp"; 
		}
	}
  }
  $hash->{PARTIAL} = $SIGNALduinodata;
}



sub SIGNALduino_KeepAlive($){
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	return if ($hash->{DevState} eq 'disconnected');
	
	#SIGNALduino_Log3 $name,4 , "$name/KeepAliveOk: " . $hash->{keepalive}{ok};
	if (!$hash->{keepalive}{ok}) {
		delete($hash->{getcmd});
		if ($hash->{keepalive}{retry} >= SDUINO_KEEPALIVE_MAXRETRY) {
			SIGNALduino_Log3 $name,3 , "$name/keepalive not ok, retry count reached. Reset";
			$hash->{DevState} = 'INACTIVE';
			SIGNALduino_ResetDevice($hash);
			return;
		}
		else {
			my $logLevel = 3;
			$hash->{keepalive}{retry} ++;
			if ($hash->{keepalive}{retry} == 1) {
				$logLevel = 4;
			}
			SIGNALduino_Log3 $name, $logLevel, "$name/KeepAlive not ok, retry = " . $hash->{keepalive}{retry} . " -> get ping";
			$hash->{getcmd}->{cmd} = "ping";
			SIGNALduino_AddSendQueue($hash, "P");
			#SIGNALduino_SimpleWrite($hash, "P");
		}
	}
	else {
		SIGNALduino_Log3 $name,4 , "$name/keepalive ok, retry = " . $hash->{keepalive}{retry};
	}
	$hash->{keepalive}{ok} = 0;
	
	InternalTimer(gettimeofday() + SDUINO_KEEPALIVE_TIMEOUT, "SIGNALduino_KeepAlive", $hash);
}


### Helper Subs >>>


## Parses a HTTP Response for example for flash via http download
sub SIGNALduino_ParseHttpResponse
{
	
	my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if($err ne "")               											 		# wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
        SIGNALduino_Log3 $name, 3, "$name: error while requesting ".$param->{url}." - $err";    		# Eintrag fuers Log
    }
    elsif($param->{code} eq "200" && $data ne "")                                                       		# wenn die Abfrage erfolgreich war ($data enthaelt die Ergebnisdaten des HTTP Aufrufes)
    {
    	
        SIGNALduino_Log3 $name, 3, "url ".$param->{url}." returned: ".length($data)." bytes Data";  # Eintrag fuers Log
		    	
    	if ($param->{command} eq "flash")
    	{
	    	my $filename;
	    	
	    	if ($param->{httpheader} =~ /Content-Disposition: attachment;.?filename=\"?([-+.\w]+)?\"?/)
			{ 
				$filename = $1;
			} else {  # Filename via path if not specifyied via Content-Disposition
	    		($filename = $param->{path}) =~s/.*\///;
			}
			
	    	SIGNALduino_Log3 $name, 3, "$name: Downloaded $filename firmware from ".$param->{host};
	    	SIGNALduino_Log3 $name, 5, "$name: Header = ".$param->{httpheader};
	
			
		   	$filename = "FHEM/firmware/" . $filename;
			open(my $file, ">", $filename) or die $!;
			print $file $data;
			close $file;
	
			# Den Flash Befehl mit der soebene heruntergeladenen Datei ausfuehren
			SIGNALduino_Log3 $name, 3, "calling set ".$param->{command}." $filename";    		# Eintrag fuers Log

			SIGNALduino_Set($hash,$name,$param->{command},$filename); # $hash->{SetFn}
			
    	}
    } else {
    	SIGNALduino_Log3 $name, 3, "$name: undefined error while requesting ".$param->{url}." - $err - code=".$param->{code};    		# Eintrag fuers Log
    }
}

sub SIGNALduino_splitMsg
{
  my $txt = shift;
  my $delim = shift;
  my @msg_parts = split(/$delim/,$txt);
  
  return @msg_parts;
}
# $value  - $set <= $tolerance
sub SIGNALduino_inTol($$$)
{
	#Debug "sduino abs \($_[0] - $_[1]\) <= $_[2] ";
	return (abs($_[0]-$_[1])<=$_[2]);
}


 # - - - - - - - - - - - -
 #=item SIGNALduino_PatternExists()
 #This functons, needs reference to $hash, @array of values to search and %patternList where to find the matches.
# 
# Will return -1 if pattern is not found or a string, containing the indexes which are in tolerance and have the smallest gap to what we searched
# =cut


# 01232323242423       while ($message =~ /$pstr/g) { $count++ }


sub SIGNALduino_PatternExists
{
	my ($hash,$search,$patternList,$data) = @_;
	#my %patternList=$arg3;
	#Debug "plist: ".Dumper($patternList) if($debug); 
	#Debug "searchlist: ".Dumper($search) if($debug);


	
	my $searchpattern;
	my $valid=1;  
	my @pstr;
	my $debug = AttrVal($hash->{NAME},"debug",0);
	
	my $i=0;
	
	my $maxcol=0;
	
	foreach $searchpattern (@{$search}) # z.B. [1, -4] 
	{
		#my $patt_id;
		# Calculate tolernace for search
		#my $tol=abs(abs($searchpattern)>=2 ?$searchpattern*0.3:$searchpattern*1.5);
		my $tol=abs(abs($searchpattern)>3 ? abs($searchpattern)>16 ? $searchpattern*0.18 : $searchpattern*0.3 : 1);  #tol is minimum 1 or higer, depending on our searched pulselengh
		

		Debug "tol: looking for ($searchpattern +- $tol)" if($debug);		
		
		my %pattern_gap ; #= {};
		# Find and store the gap of every pattern, which is in tolerance
		%pattern_gap = map { $_ => abs($patternList->{$_}-$searchpattern) } grep { abs($patternList->{$_}-$searchpattern) <= $tol} (keys %$patternList);
		if (scalar keys %pattern_gap > 0) 
		{
			Debug "index => gap in tol (+- $tol) of pulse ($searchpattern) : ".Dumper(\%pattern_gap) if($debug);
			# Extract fist pattern, which is nearst to our searched value
			my @closestidx = (sort {$pattern_gap{$a} <=> $pattern_gap{$b}} keys %pattern_gap);
			
			my $idxstr="";
			my $r=0;
			
			while (my ($item) = splice(@closestidx, 0, 1)) 
			{
				$pstr[$i][$r]=$item; 
				$r++;
				Debug "closest pattern has index: $item" if($debug);
			}
			$valid=1;
		} else {
			# search is not found, return -1
			return -1;
			last;	
		}
		$i++;
		#return ($valid ? $pstr : -1);  # return $pstr if $valid or -1

		
		#foreach $patt_id (keys %$patternList) {
			#Debug "$patt_id. chk ->intol $patternList->{$patt_id} $searchpattern $tol"; 
			#$valid =  SIGNALduino_inTol($patternList->{$patt_id}, $searchpattern, $tol);
			#if ( $valid) #one pulse found in tolerance, search next one
			#{
			#	$pstr="$pstr$patt_id";
			#	# provide this index for further lookup table -> {$patt_id =  $searchpattern}
			#	Debug "pulse found";
			#	last ; ## Exit foreach loop if searched pattern matches pattern in list
			#}
		#}
		#last if (!$valid);  ## Exit loop if a complete iteration has not found anything
	}
	my @results = ('');
	
	foreach my $subarray (@pstr)
	{
	    @results = map {my $res = $_; map $res.$_, @$subarray } @results;
	}
			
	foreach my $search (@results)
	{
		Debug "looking for substr $search" if($debug);
			
		return $search if (index( ${$data}, $search) >= 0);
	}
	
	return -1;
	
	#return ($valid ? @results : -1);  # return @pstr if $valid or -1
}

#SIGNALduino_MatchSignalPattern{$hash,@array, %hash, @array, $scalar}; not used >v3.1.3
sub SIGNALduino_MatchSignalPattern($\@\%\@$){

	my ( $hash, $signalpattern,  $patternList,  $data_array, $idx) = @_;
    my $name = $hash->{NAME};
	#print Dumper($patternList);		
	#print Dumper($idx);		
	#Debug Dumper($signalpattern) if ($debug);		
	my $tol="0.2";   # Tolerance factor
	my $found=0;
	my $debug = AttrVal($hash->{NAME},"debug",0);
	
	foreach ( @{$signalpattern} )
	{
			#Debug " $idx check: ".$patternList->{$data_array->[$idx]}." == ".$_;		
			Debug "$name: idx: $idx check: abs(". $patternList->{$data_array->[$idx]}." - ".$_.") > ". ceil(abs($patternList->{$data_array->[$idx]}*$tol)) if ($debug);		
			  
			#print "\n";;
			#if ($patternList->{$data_array->[$idx]} ne $_ ) 
			### Nachkommastelle von ceil!!!
			if (!defined( $patternList->{$data_array->[$idx]})){
				Debug "$name: Error index ($idx) does not exist!!" if ($debug);

				return -1;
			}
			if (abs($patternList->{$data_array->[$idx]} - $_)  > ceil(abs($patternList->{$data_array->[$idx]}*$tol)))
			{
				return -1;		## Pattern does not match, return -1 = not matched
			}
			$found=1;
			$idx++;
	}
	if ($found)
	{
		return $idx;			## Return new Index Position
	}
	
}




sub SIGNALduino_b2h {
    my $num   = shift;
    my $WIDTH = 4;
    my $index = length($num) - $WIDTH;
    my $hex = '';
    do {
        my $width = $WIDTH;
        if ($index < 0) {
            $width += $index;
            $index = 0;
        }
        my $cut_string = substr($num, $index, $width);
        $hex = sprintf('%X', oct("0b$cut_string")) . $hex;
        $index -= $WIDTH;
    } while ($index > (-1 * $WIDTH));
    return $hex;
}

sub SIGNALduino_Split_Message($$)
{
	my $rmsg = shift;
	my $name = shift;
	my %patternList;
	my $clockidx;
	my $syncidx;
	my $rawData;
	my $clockabs;
	my $mcbitnum;
	my $rssi;
	
	my @msg_parts = SIGNALduino_splitMsg($rmsg,';');			## Split message parts by ";"
	my %ret;
	my $debug = AttrVal($name,"debug",0);
	
	foreach (@msg_parts)
	{
		#Debug "$name: checking msg part:( $_ )" if ($debug);

		#if ($_ =~ m/^MS/ or $_ =~ m/^MC/ or $_ =~ m/^Mc/ or $_ =~ m/^MU/) 		#### Synced Message start
		if ($_ =~ m/^M./)
		{
			$ret{messagetype} = $_;
		}
		elsif ($_ =~ m/^P\d=-?\d{2,}/ or $_ =~ m/^[SL][LH]=-?\d{2,}/) 		#### Extract Pattern List from array
		{
		   $_ =~ s/^P+//;  
		   $_ =~ s/^P\d//;  
		   my @pattern = split(/=/,$_);
		   
		   $patternList{$pattern[0]} = $pattern[1];
		   Debug "$name: extracted  pattern @pattern \n" if ($debug);
		}
		elsif($_ =~ m/D=\d+/ or $_ =~ m/^D=[A-F0-9]+/) 		#### Message from array

		{
			$_ =~ s/D=//;  
			$rawData = $_ ;
			Debug "$name: extracted  data $rawData\n" if ($debug);
			$ret{rawData} = $rawData;

		}
		elsif($_ =~ m/^SP=\d{1}/) 		#### Sync Pulse Index
		{
			(undef, $syncidx) = split(/=/,$_);
			Debug "$name: extracted  syncidx $syncidx\n" if ($debug);
			#return undef if (!defined($patternList{$syncidx}));
			$ret{syncidx} = $syncidx;

		}
		elsif($_ =~ m/^CP=\d{1}/) 		#### Clock Pulse Index
		{
			(undef, $clockidx) = split(/=/,$_);
			Debug "$name: extracted  clockidx $clockidx\n" if ($debug);;
			#return undef if (!defined($patternList{$clockidx}));
			$ret{clockidx} = $clockidx;
		}
		elsif($_ =~ m/^L=\d/) 		#### MC bit length
		{
			(undef, $mcbitnum) = split(/=/,$_);
			Debug "$name: extracted  number of $mcbitnum bits\n" if ($debug);;
			$ret{mcbitnum} = $mcbitnum;
		}
		
		elsif($_ =~ m/^C=\d+/) 		#### Message from array
		{
			$_ =~ s/C=//;  
			$clockabs = $_ ;
			Debug "$name: extracted absolute clock $clockabs \n" if ($debug);
			$ret{clockabs} = $clockabs;
		}
		elsif($_ =~ m/^R=\d+/)		### RSSI ###
		{
			$_ =~ s/R=//;
			$rssi = $_ ;
			Debug "$name: extracted RSSI $rssi \n" if ($debug);
			$ret{rssi} = $rssi;
		}  else {
			Debug "$name: unknown Message part $_" if ($debug);;
		}
		#print "$_\n";
	}
	$ret{pattern} = {%patternList}; 
	return %ret;
}



# Function which dispatches a message if needed.
sub SIGNALduno_Dispatch($$$$$)
{
	my ($hash, $rmsg, $dmsg, $rssi, $id) = @_;
	my $name = $hash->{NAME};
	
	if (!defined($dmsg))
	{
		SIGNALduino_Log3 $name, 5, "$name Dispatch: dmsg is undef. Skipping dispatch call";
		return;
	}
	
	#SIGNALduino_Log3 $name, 5, "$name: Dispatch DMSG: $dmsg";
	
	my $DMSGgleich = 1;
	if ($dmsg eq $hash->{LASTDMSG}) {
		SIGNALduino_Log3 $name, SDUINO_DISPATCH_VERBOSE, "$name Dispatch: $dmsg, test gleich";
	} else {
		if (defined($hash->{DoubleMsgIDs}{$id})) {
			$DMSGgleich = 0;
			SIGNALduino_Log3 $name, SDUINO_DISPATCH_VERBOSE, "$name Dispatch: $dmsg, test ungleich";
		}
		else {
			SIGNALduino_Log3 $name, SDUINO_DISPATCH_VERBOSE, "$name Dispatch: $dmsg, test ungleich: disabled";
		}
		$hash->{LASTDMSG} = $dmsg;
	}

   if ($DMSGgleich) {
	#Dispatch if dispatchequals is provided in protocol definition or only if $dmsg is different from last $dmsg, or if 2 seconds are between transmits
	if ( (SIGNALduino_getProtoProp($id,'dispatchequals',0) eq 'true') || ($hash->{DMSG} ne $dmsg) || ($hash->{TIME}+2 < time() ) )   { 
		$hash->{MSGCNT}++;
		$hash->{TIME} = time();
		$hash->{DMSG} = $dmsg;
		$hash->{EQMSGCNT} = 0;
		#my $event = 0;
		if (substr(ucfirst($dmsg),0,1) eq 'U') { # u oder U
			#$event = 1;
			DoTrigger($name, "DMSG " . $dmsg);
			return if (substr($dmsg,0,1) eq 'U') # Fuer $dmsg die mit U anfangen ist kein Dispatch notwendig, da es dafuer kein Modul gibt klein u wird dagegen dispatcht
		}
		#readingsSingleUpdate($hash, "state", $hash->{READINGS}{state}{VAL}, $event);
		
		if (defined($ProtocolListSIGNALduino{$id}{developId}) && substr($ProtocolListSIGNALduino{$id}{developId},0,1) eq "m") {
			my $devid = "m$id";
			my $develop = lc(AttrVal($name,"development",""));
			if ($develop !~ m/$devid/) {		# kein dispatch wenn die Id nicht im Attribut development steht
				SIGNALduino_Log3 $name, 3, "$name: ID=$devid skiped dispatch (developId=m). To use, please add m$id to the attr development";
				return;
			}
		}
		
		$hash->{RAWMSG} = $rmsg;
		my %addvals = (DMSG => $dmsg);
		if (AttrVal($name,"suppressDeviceRawmsg",0) == 0) {
			$addvals{RAWMSG} = $rmsg
		}
		if(defined($rssi)) {
			$hash->{RSSI} = $rssi;
			$addvals{RSSI} = $rssi;
			$rssi .= " dB,"
		}
		else {
			$rssi = "";
		}
		
		$dmsg = lc($dmsg) if ($id eq '74');
		SIGNALduino_Log3 $name, 4, "$name Dispatch: $dmsg, $rssi dispatch";
		Dispatch($hash, $dmsg, \%addvals);  ## Dispatch to other Modules 
		
	}	else {
		$hash->{EQMSGCNT}++;
		SIGNALduino_Log3 $name, 4, "$name Dispatch: $dmsg, Dropped (" . $hash->{EQMSGCNT} . ") due to short time and equal msg";
	}
   }
}

sub
SIGNALduino_Parse_MS($$$$%)
{
	my ($hash, $iohash, $name, $rmsg,%msg_parts) = @_;

	my $protocolid;
	my $syncidx=$msg_parts{syncidx};			
	my $clockidx=$msg_parts{clockidx};				
	my $rawRssi=$msg_parts{rssi};
	my $protocol=undef;
	my $rawData=$msg_parts{rawData};
	my %patternList;
	my $rssi;
	if (defined($rawRssi)) {
		$rssi = ($rawRssi>=128 ? (($rawRssi-256)/2-74) : ($rawRssi/2-74)); # todo: passt dies so? habe ich vom 00_cul.pm
	}
    #$patternList{$_} = $msg_parts{rawData}{$_] for keys %msg_parts{rawData};

	#$patternList = \%msg_parts{pattern};

	#Debug "Message splitted:";
	#Debug Dumper(\@msg_parts);

	my $debug = AttrVal($iohash->{NAME},"debug",0);

	
	if (defined($clockidx) and defined($syncidx))
	{
		
		## Make a lookup table for our pattern index ids
		#Debug "List of pattern:";
		my $clockabs= $msg_parts{pattern}{$msg_parts{clockidx}};
		return undef if ($clockabs == 0); 
		$patternList{$_} = round($msg_parts{pattern}{$_}/$clockabs,1) for keys %{$msg_parts{pattern}};
	
		
 		#Debug Dumper(\%patternList);		

		#my $syncfact = $patternList{$syncidx}/$patternList{$clockidx};
		#$syncfact=$patternList{$syncidx};
		#Debug "SF=$syncfact";
		#### Convert rawData in Message
		my $signal_length = length($rawData);        # Length of data array

		## Iterate over the data_array and find zero, one, float and sync bits with the signalpattern
		## Find matching protocols
		my $id;
		my $message_dispatched=0;
		foreach $id (@{$hash->{msIdList}}) {
			
			my $valid=1;
			#$debug=1;
			Debug "Testing against Protocol id $id -> $ProtocolListSIGNALduino{$id}{name}"  if ($debug);

			# Check Clock if is it in range
			$valid=SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{clockabs},$clockabs,$clockabs*0.30) if ($ProtocolListSIGNALduino{$id}{clockabs} > 0);
			Debug "validclock = $valid"  if ($debug);
			
			next if (!$valid) ;

			my $bit_length = ($signal_length-(scalar @{$ProtocolListSIGNALduino{$id}{sync}}))/((scalar @{$ProtocolListSIGNALduino{$id}{one}} + scalar @{$ProtocolListSIGNALduino{$id}{zero}})/2);

			#Check calculated min length
			$valid = $valid && $ProtocolListSIGNALduino{$id}{length_min} <= $bit_length if (exists $ProtocolListSIGNALduino{$id}{length_min}); 
			#Check calculated max length
			$valid = $valid && $ProtocolListSIGNALduino{$id}{length_max} >= $bit_length if (exists $ProtocolListSIGNALduino{$id}{length_max});

			#Log3 $name, 5, "$name: ID $id MS expecting $bit_length bits in signal, length_rawData=$signal_length";
			next if (!$valid);

			#Debug Dumper(@{$ProtocolListSIGNALduino{$id}{sync}});
			Debug "Searching in patternList: ".Dumper(\%patternList) if($debug);

			Debug "searching sync: @{$ProtocolListSIGNALduino{$id}{sync}}[0] @{$ProtocolListSIGNALduino{$id}{sync}}[1]" if($debug); # z.B. [1, -18] 
			#$valid = $valid && SIGNALduino_inTol($patternList{$clockidx}, @{$ProtocolListSIGNALduino{$id}{sync}}[0], 3); #sync in tolerance
			#$valid = $valid && SIGNALduino_inTol($patternList{$syncidx}, @{$ProtocolListSIGNALduino{$id}{sync}}[1], 3); #sync in tolerance
			
			my $pstr;
			my %patternLookupHash=();

			$valid = $valid && ($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{sync}},\%patternList,\$rawData)) >=0;
			Debug "Found matched sync with indexes: ($pstr)" if ($debug && $valid);
			$patternLookupHash{$pstr}="" if ($valid); ## Append Sync to our lookuptable
			my $syncstr=$pstr; # Store for later start search

			Debug "sync not found " if (!$valid && $debug); # z.B. [1, -18] 

			next if (!$valid) ;

			$valid = $valid && ($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{one}},\%patternList,\$rawData)) >=0;
			Debug "Found matched one with indexes: ($pstr)" if ($debug && $valid);
			$patternLookupHash{$pstr}="1" if ($valid); ## Append Sync to our lookuptable
			#Debug "added $pstr " if ($debug && $valid);
			Debug "one pattern not found" if ($debug && !$valid);


			$valid = $valid && ($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{zero}},\%patternList,\$rawData)) >=0;
			Debug "Found matched zero with indexes: ($pstr)" if ($debug && $valid);
			$patternLookupHash{$pstr}="0" if ($valid); ## Append Sync to our lookuptable
			Debug "zero pattern not found" if ($debug && !$valid);
			
			if (defined($ProtocolListSIGNALduino{$id}{float}))
			{
				my $floatValid = ($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{float}},\%patternList,\$rawData)) >=0;
				Debug "Found matched float with indexes: ($pstr)" if ($debug && $floatValid);
				$patternLookupHash{$pstr}="F" if ($floatValid); ## Append Sync to our lookuptable
				Debug "float pattern not found" if ($debug && !$floatValid);
			}
			#Debug "added $pstr " if ($debug && $valid);

			next if (!$valid) ;
			#Debug "Pattern Lookup Table".Dumper(%patternLookupHash);
			## Check somethin else

		
			#Anything seems to be valid, we can start decoding this.			

			Log3 $name, 4, "$name: Matched MS Protocol id $id -> $ProtocolListSIGNALduino{$id}{name}, bitLen=$bit_length" if ($valid);
			my $signal_width= @{$ProtocolListSIGNALduino{$id}{one}};
			#Debug $signal_width;
			
			
			my @bit_msg;							# array to store decoded signal bits

			#for (my $i=index($rawData,SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{sync}}))+$signal_width;$i<length($rawData);$i+=$signal_width)
			#for (my $i=scalar@{$ProtocolListSIGNALduino{$id}{sync}};$i<length($rawData);$i+=$signal_width)
			my $message_start =index($rawData,$syncstr)+length($syncstr);
			Log3 $name, 5, "$name: Starting demodulation at Position $message_start";
			
			for (my $i=$message_start;$i<length($rawData);$i+=$signal_width)
			{
				my $sig_str= substr($rawData,$i,$signal_width);
				#Log3 $name, 5, "demodulating $sig_str";
				#Debug $patternLookupHash{substr($rawData,$i,$signal_width)}; ## Get $signal_width number of chars from raw data string
				if (exists $patternLookupHash{$sig_str}) { ## Add the bits to our bit array
					push(@bit_msg,$patternLookupHash{$sig_str})
				} else {
					Log3 $name, 5, "$name: Found wrong signalpattern, catched ".scalar @bit_msg." bits, aborting demodulation";
					last;
				}
			}
			
			Debug "$name: decoded message raw (@bit_msg), ".@bit_msg." bits\n" if ($debug);;

			my $padwith = defined($ProtocolListSIGNALduino{$id}{paddingbits}) ? $ProtocolListSIGNALduino{$id}{paddingbits} : 4;
			
			my $i=0;
			while (scalar @bit_msg % $padwith > 0)  ## will pad up full nibbles per default or full byte if specified in protocol
			{
				push(@bit_msg,'0');
				$i++;
			}
			Debug "$name padded $i bits to bit_msg array" if ($debug);
				
			#my $logmsg = SIGNALduino_padbits(@bit_msg,$padwith);
			
			#Check converted message against lengths
			$valid = $valid && $ProtocolListSIGNALduino{$id}{length_min} <= scalar @bit_msg  if (defined($ProtocolListSIGNALduino{$id}{length_min})); 
			$valid = $valid && $ProtocolListSIGNALduino{$id}{length_max} >= scalar @bit_msg  if (defined($ProtocolListSIGNALduino{$id}{length_max}));
			next if (!$valid);  
			
			my ($rcode,@retvalue) = SIGNALduino_callsub('postDemodulation',$ProtocolListSIGNALduino{$id}{postDemodulation},$name,@bit_msg);
			next if ($rcode < 1 );
			#Log3 $name, 5, "$name: postdemodulation value @retvalue";
			
			@bit_msg = @retvalue;
			undef(@retvalue); undef($rcode);
			
			#my $dmsg = sprintf "%02x", oct "0b" . join "", @bit_msg;			## Array -> String -> bin -> hex
			my $dmsg = SIGNALduino_b2h(join "", @bit_msg);
			my $postamble = $ProtocolListSIGNALduino{$id}{postamble};
			#if (defined($rawRssi)) {
				#if (defined($ProtocolListSIGNALduino{$id}{preamble}) && $ProtocolListSIGNALduino{$id}{preamble} eq "s") {
				#	$postamble = sprintf("%02X", $rawRssi);
				#} elsif ($id eq "7") {
				#        $postamble = "#R" . sprintf("%02X", $rawRssi);
				#}
			#}
			$dmsg = "$dmsg".$postamble if (defined($postamble));
			$dmsg = "$ProtocolListSIGNALduino{$id}{preamble}"."$dmsg" if (defined($ProtocolListSIGNALduino{$id}{preamble}));
			
			if (defined($rssi)) {
				Log3 $name, 4, "$name: Decoded MS Protocol id $id dmsg $dmsg length " . scalar @bit_msg . " RSSI = $rssi";
			} else {
				Log3 $name, 4, "$name: Decoded MS Protocol id $id dmsg $dmsg length " . scalar @bit_msg;
			}
			
			#my ($rcode,@retvalue) = SIGNALduino_callsub('preDispatchfunc',$ProtocolListSIGNALduino{$id}{preDispatchfunc},$name,$dmsg);
			#next if (!$rcode);
			#$dmsg = @retvalue;
			#undef(@retvalue); undef($rcode);
			
			my $modulematch = undef;
			if (defined($ProtocolListSIGNALduino{$id}{modulematch})) {
				$modulematch = $ProtocolListSIGNALduino{$id}{modulematch};
			}
			if (!defined($modulematch) || $dmsg =~ m/$modulematch/) {
				Debug "$name: dispatching now msg: $dmsg" if ($debug);
				#if (defined($ProtocolListSIGNALduino{$id}{developId}) && substr($ProtocolListSIGNALduino{$id}{developId},0,1) eq "m") {
				#	my $devid = "m$id";
				#	my $develop = lc(AttrVal($name,"development",""));
				#	if ($develop !~ m/$devid/) {		# kein dispatch wenn die Id nicht im Attribut development steht
				#		Log3 $name, 3, "$name: ID=$devid skiped dispatch (developId=m). To use, please add m$id to the attr development";
				#		next;
				#	}
				#}
				SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
				$message_dispatched=1;
			}
		}
		
		return 0 if (!$message_dispatched);
		
		return 1;
		

	}
}


## //Todo: check list as reference
sub SIGNALduino_padbits(\@$)
{
	my $i=@{$_[0]} % $_[1];
	while (@{$_[0]} % $_[1] > 0)  ## will pad up full nibbles per default or full byte if specified in protocol
	{
		push(@{$_[0]},'0');
	}
	return " padded $i bits to bit_msg array";
}

# - - - - - - - - - - - -
#=item SIGNALduino_getProtoProp()
#This functons, will return a value from the Protocolist and check if it is defined optional you can specify a optional default value that will be reurned
# 
# returns "" if the var is not defined
# =cut
#  $id, $propertyname,

sub SIGNALduino_getProtoProp
{
	my ($id,$propNameLst,$default) = @_;
	
	#my $id = shift;
	#my $propNameLst = shift;
	return $ProtocolListSIGNALduino{$id}{$propNameLst} if defined($ProtocolListSIGNALduino{$id}{$propNameLst});
	return $default; # Will return undef if $default is not provided
	#return undef;
}

sub SIGNALduino_Parse_MU($$$$@)
{
	my ($hash, $iohash, $name, $rmsg,%msg_parts) = @_;

	my $protocolid;
	my $clockidx=$msg_parts{clockidx};
	my $rssi=$msg_parts{rssi};
	my $rawData;
	my %patternListRaw;
	my $message_dispatched=0;
	my $debug = AttrVal($iohash->{NAME},"debug",0);
	my $maxRepeat = AttrVal($name,"maxMuMsgRepeat", 4);
	my $dummy = IsDummy($iohash->{NAME});
	
	if (defined($rssi)) {
		$rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74)); # todo: passt dies so? habe ich vom 00_cul.pm
	}
	
    Debug "$name: processing unsynced message\n" if ($debug);

	my $clockabs = 1;  #Clock will be fetched from Protocol if possible
	#$patternListRaw{$_} = floor($msg_parts{pattern}{$_}/$clockabs) for keys $msg_parts{pattern};
	$patternListRaw{$_} = $msg_parts{pattern}{$_} for keys %{$msg_parts{pattern}};

	
	if (defined($clockidx))
	{
		
		## Make a lookup table for our pattern index ids
		#Debug "List of pattern:"; 		#Debug Dumper(\%patternList);		

		## Find matching protocols
		my $id;
		foreach $id (@{$hash->{muIdList}}) {
			
			#my $valid=1;
			$clockabs= $ProtocolListSIGNALduino{$id}{clockabs};
			my %patternList;
			$rawData=$msg_parts{rawData};
			if (exists($ProtocolListSIGNALduino{$id}{filterfunc}))
			{
				my $method = $ProtocolListSIGNALduino{$id}{filterfunc};
		   		if (!exists &$method)
				{
					SIGNALduino_Log3 $name, 5, "$name: Error: Unknown filtermethod=$method. Please define it in file $0";
					next;
				} else {					
					SIGNALduino_Log3 $name, 5, "$name: for MU Protocol id $id, applying filterfunc $method";

				    no strict "refs";
					(my $count_changes,$rawData,my %patternListRaw_tmp) = $method->($name,$id,$rawData,%patternListRaw);				
				    use strict "refs";

					%patternList = map { $_ => round($patternListRaw_tmp{$_}/$clockabs,1) } keys %patternListRaw_tmp; 
				}
			} else {
				%patternList = map { $_ => round($patternListRaw{$_}/$clockabs,1) } keys %patternListRaw; 
			}
			
			my $msgclock;
			my $clocksource = "";
			my $clockMsg = "";
			if (defined($ProtocolListSIGNALduino{$id}{clockpos}) && defined($ProtocolListSIGNALduino{$id}{clockpos}[0]))
			{
				$clocksource = $ProtocolListSIGNALduino{$id}{clockpos}[0];
				if ($clocksource ne "one" && $clocksource ne "zero") {	# wenn clocksource nicht one oder zero ist, dann wird CP= aus der Nachricht verwendet
					$msgclock = $msg_parts{pattern}{$clockidx};
					if (!SIGNALduino_inTol($clockabs,$msgclock,$msgclock*0.30)) {
						Log3 $name, 5, "$name: clock for MU Protocol id $id, clockId=$clockabs, clockmsg=$msgclock (cp) is not in tol=" . $msgclock*0.30 if ($dummy);
						next if (SDUINO_PARSE_MU_CLOCK_CHECK);
					} else {
						$clockMsg = ", msgClock=$msgclock (cp) is in tol" if ($dummy);
					}
				}
			}
			
			#Debug Dumper(\%patternList);	
					
			Debug "Testing against Protocol id $id -> $ProtocolListSIGNALduino{$id}{name}"  if ($debug);

			Debug "Searching in patternList: ".Dumper(\%patternList) if($debug);

			my @msgStartLst;
			my $startStr=""; # Default match if there is no start pattern available
			my $message_start=0 ;
			my $startLogStr="";
			
			if (defined($ProtocolListSIGNALduino{$id}{start}))	# wenn start definiert ist, dann startStr ermitteln und in rawData suchen und in der rawData alles bis zum startStr abschneiden
			{
				@msgStartLst = $ProtocolListSIGNALduino{$id}{start};
				Debug "msgStartLst: ".Dumper(@msgStartLst)  if ($debug);
				
				if ( ($startStr=SIGNALduino_PatternExists($hash,@msgStartLst,\%patternList,\$rawData)) eq -1)
				{
					Log3 $name, 5, "$name: start pattern for MU Protocol id $id -> $ProtocolListSIGNALduino{$id}{name} not found, aborting" if ($dummy);
					next;
				}
				Debug "startStr is: $startStr" if ($debug);
				
				$message_start = index($rawData, $startStr);
				if ($message_start >= 0) {
					$rawData = substr($rawData, $message_start);
					$startLogStr = "StartStr: $startStr cut Pos $message_start" . "; ";
					Debug "rawData = $rawData" if ($debug);
					Debug "startStr $startStr found. Message starts at $message_start" if ($debug);
				} else {
					Debug "startStr $startStr not found." if ($debug);
					next;
				}
			}
			
			my %patternLookupHash=();
			my $pstr="";
			my $zeroRegex ="";
			my $oneRegex ="";
			my $floatRegex ="";
			my $protocListClock;
			
			if (($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{one}},\%patternList,\$rawData)) eq -1)
			{
				Log3 $name, 5, "$name: one pattern for MU Protocol id $id not found, aborting" if ($dummy);
				next;
			}
			Debug "Found matched one" if ($debug);
			if ($clocksource eq "one")		# clocksource one, dann die clock aus one holen
			{
				$msgclock = $msg_parts{pattern}{substr($pstr, $ProtocolListSIGNALduino{$id}{clockpos}[1], 1)};
				$protocListClock = $clockabs * $ProtocolListSIGNALduino{$id}{one}[$ProtocolListSIGNALduino{$id}{clockpos}[1]];
				if (!SIGNALduino_inTol($protocListClock,$msgclock,$msgclock*0.30)) {
					Log3 $name, 5, "$name: clock for MU Protocol id $id, protocClock=$protocListClock, msgClock=$msgclock (one) is not in tol=" . $msgclock*0.30 if ($dummy);
					next if (SDUINO_PARSE_MU_CLOCK_CHECK);
				} else {
					$clockMsg = ", msgClock=$msgclock (one) is in tol" if ($dummy);
				}
			}
			$oneRegex=$pstr;
			$patternLookupHash{$pstr}="1";		## Append one to our lookuptable
			Debug "added $pstr " if ($debug);
			
			if (scalar @{$ProtocolListSIGNALduino{$id}{zero}} >0)
			{
				if  (($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{zero}},\%patternList,\$rawData)) eq -1)
				{
					Log3 $name, 5, "$name: zero pattern for MU Protocol id $id not found, aborting" if ($dummy);
					next;
				}
				Debug "Found matched zero" if ($debug);
				if ($clocksource eq "zero")		# clocksource zero, dann die clock aus zero holen
				{
					$msgclock = $msg_parts{pattern}{substr($pstr, $ProtocolListSIGNALduino{$id}{clockpos}[1], 1)};
					$protocListClock = $clockabs * $ProtocolListSIGNALduino{$id}{zero}[$ProtocolListSIGNALduino{$id}{clockpos}[1]];
					if (!SIGNALduino_inTol($protocListClock,$msgclock,$msgclock*0.30)) {
						Log3 $name, 5, "$name: clock for MU Protocol id $id, protocClock=$protocListClock, msgClock=$msgclock (zero) is not in tol=" . $msgclock*0.30 if ($dummy);
						next if (SDUINO_PARSE_MU_CLOCK_CHECK);
					} else {
						$clockMsg = ", msgClock=$msgclock (zero) is in tol" if ($dummy);
					}
				}
				$zeroRegex='|' . $pstr;
				$patternLookupHash{$pstr}="0";		## Append zero to our lookuptable
				Debug "added $pstr " if ($debug);
			}

			if (defined($ProtocolListSIGNALduino{$id}{float}) && ($pstr=SIGNALduino_PatternExists($hash,\@{$ProtocolListSIGNALduino{$id}{float}},\%patternList,\$rawData)) >=0)
			{
				Debug "Found matched float" if ($debug);
				$floatRegex='|' . $pstr;
				$patternLookupHash{$pstr}="F";		## Append float to our lookuptable
				Debug "added $pstr " if ($debug);
			}
			
			#Debug "Pattern Lookup Table".Dumper(%patternLookupHash);
			SIGNALduino_Log3 $name, 4, "$name: Fingerprint for MU Protocol id $id -> $ProtocolListSIGNALduino{$id}{name} matches, trying to demodulate$clockMsg";
			
			my $signal_width= @{$ProtocolListSIGNALduino{$id}{one}};
			my $length_min;
			if (defined($ProtocolListSIGNALduino{$id}{length_min})) {
				$length_min = $ProtocolListSIGNALduino{$id}{length_min};
			} else {
				$length_min = SDUINO_PARSE_DEFAULT_LENGHT_MIN;
			}
			my $length_max = 0;
			$length_max = $ProtocolListSIGNALduino{$id}{length_max} if (defined($ProtocolListSIGNALduino{$id}{length_max}));
			
			my $signalRegex = "(?:" . $oneRegex . $zeroRegex . $floatRegex . "){$length_min,}";
			my $regex="(?:$startStr)($signalRegex)";
			Debug "Regex is: $regex" if ($debug);
			
			my $repeat=0;
			my $repeatStr="";
			my $length_str;
			my $bit_msg_length;
			my $nrRestart = 0;
			
			while ( $rawData =~ m/$regex/g) {
				my @pairs = unpack "(a$signal_width)*", $1;
				$message_start = $-[0];
				$bit_msg_length = scalar @pairs;
				
				if ($length_max > 0 && $bit_msg_length > $length_max) {		# ist die Nachricht zu lang?
					$length_str = " (length $bit_msg_length to long)";
				} else {
					$length_str = "";
				}
				
				if ($nrRestart == 0) {
					SIGNALduino_Log3 $name, 5, "$name: Starting demodulation ($startLogStr" . "Signal: $signalRegex Pos $message_start) length_min_max (".$length_min."..".$length_max.") length=".$bit_msg_length;
					SIGNALduino_Log3 $name, 5, "$name: skip demodulation (length $bit_msg_length is to long)" if ($length_str ne "");
				} else {
					SIGNALduino_Log3 $name, 5, "$name: $nrRestart.restarting demodulation$length_str at Pos $message_start regex ($regex)";
				}
				
				$nrRestart++;
				next if ($length_str ne "");	# Nachricht ist zu lang
				
				
				#Anything seems to be valid, we can start decoding this.			
				
				my @bit_msg=();			# array to store decoded signal bits
				
				foreach my $sigStr (@pairs)
				{
					if (exists $patternLookupHash{$sigStr}) {
						push(@bit_msg,$patternLookupHash{$sigStr})  ## Add the bits to our bit array
					}
				}
				
					Debug "$name: demodulated message raw (@bit_msg), ".@bit_msg." bits\n" if ($debug);
					
					my ($rcode,@retvalue) = SIGNALduino_callsub('postDemodulation',$ProtocolListSIGNALduino{$id}{postDemodulation},$name,@bit_msg);
					next if ($rcode < 1 );
					@bit_msg = @retvalue;
					SIGNALduino_Log3 $name, 5, "$name: postdemodulation value @retvalue" if ($debug);
					undef(@retvalue); undef($rcode);
					
					my $bit_msg_length = scalar @bit_msg;
					my $dmsg;
					
					if (defined($ProtocolListSIGNALduino{$id}{dispatchBin})) {
						$dmsg = join ("", @bit_msg);
						SIGNALduino_Log3 $name, 5, "$name: dispatching bits: $dmsg";
					} else {
						my $anzPadding = 0;
						my $padwith = defined($ProtocolListSIGNALduino{$id}{paddingbits}) ? $ProtocolListSIGNALduino{$id}{paddingbits} : 4;
						while (scalar @bit_msg % $padwith > 0)  ## will pad up full nibbles per default or full byte if specified in protocol
						{
							push(@bit_msg,'0');
							$anzPadding++;
							Debug "$name: padding 0 bit to bit_msg array" if ($debug);
						}
						$dmsg = join ("", @bit_msg);
						if ($anzPadding == 0) {
							SIGNALduino_Log3 $name, 5, "$name: dispatching bits: $dmsg";
						} else {
							SIGNALduino_Log3 $name, 5, "$name: dispatching bits: $dmsg with anzPadding=$anzPadding";
						}
						$dmsg = SIGNALduino_b2h($dmsg);
					}
					@bit_msg=(); # clear bit_msg array
					
					$dmsg =~ s/^0+//	 if (defined($ProtocolListSIGNALduino{$id}{remove_zero})); 
					$dmsg = "$dmsg"."$ProtocolListSIGNALduino{$id}{postamble}" if (defined($ProtocolListSIGNALduino{$id}{postamble}));
					$dmsg = "$ProtocolListSIGNALduino{$id}{preamble}"."$dmsg" if (defined($ProtocolListSIGNALduino{$id}{preamble}));
					
					if (defined($rssi)) {
						SIGNALduino_Log3 $name, 4, "$name: decoded matched MU Protocol id $id dmsg $dmsg length $bit_msg_length" . $repeatStr . " RSSI = $rssi";
					} else {
						SIGNALduino_Log3 $name, 4, "$name: decoded matched MU Protocol id $id dmsg $dmsg length $bit_msg_length" . $repeatStr;
					}
					
					my $modulematch;
					if (defined($ProtocolListSIGNALduino{$id}{modulematch})) {
						$modulematch = $ProtocolListSIGNALduino{$id}{modulematch};
					}
					if (!defined($modulematch) || $dmsg =~ m/$modulematch/) {
						Debug "$name: dispatching now msg: $dmsg" if ($debug);
						#if (defined($ProtocolListSIGNALduino{$id}{developId}) && substr($ProtocolListSIGNALduino{$id}{developId},0,1) eq "m") {
						#	my $devid = "m$id";
						#	my $develop = lc(AttrVal($name,"development",""));
						#	if ($develop !~ m/$devid/) {		# kein dispatch wenn die Id nicht im Attribut development steht
						#		SIGNALduino_Log3 $name, 3, "$name: ID=$devid skiped dispatch (developId=m). To use, please add m$id to the attr development";
						#		last;
						#	}
						#}
						
						SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
						$message_dispatched=1;
					}
					
					$repeat++;
					$repeatStr = " repeat $repeat";
					last if ($repeat > $maxRepeat);	# Abbruch, wenn die max repeat anzahl erreicht ist
			}
			SIGNALduino_Log3 $name, 5, "$name: regex ($regex) did not match, aborting" if ($nrRestart == 0);
		}
		return 0 if (!$message_dispatched);
		
		return 1;
	}
}


sub
SIGNALduino_Parse_MC($$$$@)
{

	my ($hash, $iohash, $name, $rmsg,%msg_parts) = @_;
	my $clock=$msg_parts{clockabs};	     ## absolute clock
	my $rawData=$msg_parts{rawData};
	my $rssi=$msg_parts{rssi};
	my $mcbitnum=$msg_parts{mcbitnum};
	my $messagetype=$msg_parts{messagetype};
	my $bitData;
	my $dmsg;
	my $message_dispatched=0;
	my $debug = AttrVal($iohash->{NAME},"debug",0);
	if (defined($rssi)) {
		$rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74)); # todo: passt dies so? habe ich vom 00_cul.pm
	}
	
	return undef if (!$clock);
	#my $protocol=undef;
	#my %patternListRaw = %msg_parts{patternList};
	
	Debug "$name: processing manchester messag len:".length($rawData) if ($debug);
	
	my $hlen = length($rawData);
	my $blen;
	#if (defined($mcbitnum)) {
	#	$blen = $mcbitnum;
	#} else {
		$blen = $hlen * 4;
	#}
	my $id;
	
	my $rawDataInverted;
	($rawDataInverted = $rawData) =~ tr/0123456789ABCDEF/FEDCBA9876543210/;   # Some Manchester Data is inverted
	
	foreach $id (@{$hash->{mcIdList}}) {

		#next if ($blen < $ProtocolListSIGNALduino{$id}{length_min} || $blen > $ProtocolListSIGNALduino{$id}{length_max});
		#if ( $clock >$ProtocolListSIGNALduino{$id}{clockrange}[0] and $clock <$ProtocolListSIGNALduino{$id}{clockrange}[1]);
		if ( $clock >$ProtocolListSIGNALduino{$id}{clockrange}[0] and $clock <$ProtocolListSIGNALduino{$id}{clockrange}[1] and length($rawData)*4 >= $ProtocolListSIGNALduino{$id}{length_min} )
		{
			Debug "clock and min length matched"  if ($debug);

			if (defined($rssi)) {
				Log3 $name, 4, "$name: Found manchester Protocol id $id clock $clock RSSI $rssi -> $ProtocolListSIGNALduino{$id}{name}";
			} else {
				Log3 $name, 4, "$name: Found manchester Protocol id $id clock $clock -> $ProtocolListSIGNALduino{$id}{name}";
			}
			
			my $polarityInvert = 0;
			if (exists($ProtocolListSIGNALduino{$id}{polarity}) && ($ProtocolListSIGNALduino{$id}{polarity} eq 'invert'))
			{
				$polarityInvert = 1;
			}
			if ($messagetype eq 'Mc' || (defined($hash->{version}) && substr($hash->{version},0,6) eq 'V 3.2.'))
			{
				$polarityInvert = $polarityInvert ^ 1;
			}
			if ($polarityInvert == 1)
			{
		   		$bitData= unpack("B$blen", pack("H$hlen", $rawDataInverted)); 
			} else {
		   		$bitData= unpack("B$blen", pack("H$hlen", $rawData)); 
			}
			Debug "$name: extracted data $bitData (bin)\n" if ($debug); ## Convert Message from hex to bits
		   	Log3 $name, 5, "$name: extracted data $bitData (bin)";
		   	
		   	my $method = $ProtocolListSIGNALduino{$id}{method};
		    if (!exists &$method)
			{
				Log3 $name, 5, "$name: Error: Unknown function=$method. Please define it in file $0";
			} else {
				my ($rcode,$res) = $method->($name,$bitData,$id,$mcbitnum);
				if ($rcode != -1) {
					$dmsg = $res;
					$dmsg=$ProtocolListSIGNALduino{$id}{preamble}.$dmsg if (defined($ProtocolListSIGNALduino{$id}{preamble})); 
					my $modulematch;
					if (defined($ProtocolListSIGNALduino{$id}{modulematch})) {
		                $modulematch = $ProtocolListSIGNALduino{$id}{modulematch};
					}
					if (!defined($modulematch) || $dmsg =~ m/$modulematch/) {
						#if (defined($ProtocolListSIGNALduino{$id}{developId}) && substr($ProtocolListSIGNALduino{$id}{developId},0,1) eq "m") {
						#	my $devid = "m$id";
						#	my $develop = lc(AttrVal($name,"development",""));
						#	if ($develop !~ m/$devid/) {		# kein dispatch wenn die Id nicht im Attribut development steht
						#		Log3 $name, 3, "$name: ID=$devid skiped dispatch (developId=m). To use, please add m$id to the attr development";
						#		next;
						#	}
						#}
						if (SDUINO_MC_DISPATCH_VERBOSE < 5 && (SDUINO_MC_DISPATCH_LOG_ID eq '' || SDUINO_MC_DISPATCH_LOG_ID eq $id))
						{
							if (defined($rssi)) {
								Log3 $name, SDUINO_MC_DISPATCH_VERBOSE, "$name $id, $rmsg RSSI=$rssi";
							} else
							{
								Log3 $name, SDUINO_MC_DISPATCH_VERBOSE, "$name $id, $rmsg";
							}
						}
						SIGNALduno_Dispatch($hash,$rmsg,$dmsg,$rssi,$id);
						$message_dispatched=1;
					}
				} else {
					$res="undef" if (!defined($res));
					Log3 $name, 5, "$name: protocol does not match return from method: ($res)" ; 

				}
			}
		}
			
	}
	return 0 if (!$message_dispatched);
	return 1;
}


sub
SIGNALduino_Parse($$$$@)
{
  my ($hash, $iohash, $name, $rmsg, $initstr) = @_;

	#print Dumper(\%ProtocolListSIGNALduino);
	
    	
	if (!($rmsg=~ s/^\002(M.;.*;)\003/$1/)) 			# Check if a Data Message arrived and if it's complete  (start & end control char are received)
	{							# cut off start end end character from message for further processing they are not needed
		SIGNALduino_Log3 $name, AttrVal($name,"noMsgVerbose",5), "$name/noMsg Parse: $rmsg";
		return undef;
	}

	if (defined($hash->{keepalive})) {
		$hash->{keepalive}{ok}    = 1;
		$hash->{keepalive}{retry} = 0;
	}
	
	my $debug = AttrVal($iohash->{NAME},"debug",0);
	
	
	Debug "$name: incoming message: ($rmsg)\n" if ($debug);
	
	if (AttrVal($name, "rawmsgEvent", 0)) {
		DoTrigger($name, "RAWMSG " . $rmsg);
	}
	
	my %signal_parts=SIGNALduino_Split_Message($rmsg,$name);   ## Split message and save anything in an hash %signal_parts
	#Debug "raw data ". $signal_parts{rawData};
	
	
	my $dispatched;

	# Message synced type   -> MS
	if (@{$hash->{msIdList}} && $rmsg=~ m/^MS;(P\d=-?\d+;){3,8}D=\d+;CP=\d;SP=\d;/) 
	{
		$dispatched= SIGNALduino_Parse_MS($hash, $iohash, $name, $rmsg,%signal_parts);
	}
	# Message unsynced type   -> MU
  	elsif (@{$hash->{muIdList}} && $rmsg=~ m/^MU;(P\d=-?\d+;){3,8}((CP|R)=\d+;){0,2}D=\d+;/)
	{
		$dispatched=  SIGNALduino_Parse_MU($hash, $iohash, $name, $rmsg,%signal_parts);
	}
	# Manchester encoded Data   -> MC
  	elsif (@{$hash->{mcIdList}} && $rmsg=~ m/^M[cC];.*;/) 
	{
		$dispatched=  SIGNALduino_Parse_MC($hash, $iohash, $name, $rmsg,%signal_parts);
	}
	else {
		Debug "$name: unknown Messageformat, aborting\n" if ($debug);
		return undef;
	}
	
	if ( AttrVal($hash->{NAME},"verbose","0") > 4 && !$dispatched)	# bei verbose 5 wird die $rmsg in $hash->{unknownmessages} hinzugefuegt
	{
   	    my $notdisplist;
   	    my @lines;
   	    if (defined($hash->{unknownmessages}))
   	    {
   	    	$notdisplist=$hash->{unknownmessages};	      				
			@lines = split ('#', $notdisplist);   # or whatever
   	    }
		push(@lines,FmtDateTime(time())."-".$rmsg);
		shift(@lines)if (scalar @lines >25);
		$notdisplist = join('#',@lines);

		$hash->{unknownmessages}=$notdisplist;
		return undef;
		#Todo  compare Sync/Clock fact and length of D= if equal, then it's the same protocol!
	}


}


#####################################
sub
SIGNALduino_Ready($)
{
  my ($hash) = @_;

  if ($hash->{STATE} eq 'disconnected') {
    $hash->{DevState} = 'disconnected';
    return DevIo_OpenDev($hash, 1, "SIGNALduino_DoInit", 'SIGNALduino_Connect')
  }
  
  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}


sub
SIGNALduino_WriteInit($)
{
  my ($hash) = @_;
  
  # todo: ist dies so ausreichend, damit die Aenderungen uebernommen werden?
  SIGNALduino_AddSendQueue($hash,"WS36");   # SIDLE, Exit RX / TX, turn off frequency synthesizer 
  SIGNALduino_AddSendQueue($hash,"WS34");   # SRX, Enable RX. Perform calibration first if coming from IDLE and MCSM0.FS_AUTOCAL=1.
}

########################
sub
SIGNALduino_SimpleWrite(@)
{
  my ($hash, $msg, $nonl) = @_;
  return if(!$hash);
  if($hash->{TYPE} eq "SIGNALduino_RFR") {
    # Prefix $msg with RRBBU and return the corresponding SIGNALduino hash.
    ($hash, $msg) = SIGNALduino_RFR_AddPrefix($hash, $msg); 
  }

  my $name = $hash->{NAME};
  SIGNALduino_Log3 $name, 5, "$name SW: $msg";

  $msg .= "\n" unless($nonl);

  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg) if($hash->{TCPDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}

sub
SIGNALduino_Attr(@)
{
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};
	my $debug = AttrVal($name,"debug",0);
	
	$aVal= "" if (!defined($aVal));
	SIGNALduino_Log3 $name, 4, "$name: Calling Getting Attr sub with args: $cmd $aName = $aVal";
		
	if( $aName eq "Clients" ) {		## Change clientList
		$hash->{Clients} = $aVal;
		$hash->{Clients} = $clientsSIGNALduino if( !$hash->{Clients}) ;				## Set defaults
		return "Setting defaults";
	} elsif( $aName eq "MatchList" ) {	## Change matchList
		my $match_list;
		if( $cmd eq "set" ) {
			$match_list = eval $aVal;
			if( $@ ) {
				SIGNALduino_Log3 $name, 2, $name .": $aVal: ". $@;
			}
		}
		
		if( ref($match_list) eq 'HASH' ) {
		  $hash->{MatchList} = $match_list;
		} else {
		  $hash->{MatchList} = \%matchListSIGNALduino;								## Set defaults
		  SIGNALduino_Log3 $name, 2, $name .": $aVal: not a HASH using defaults" if( $aVal );
		}
	}
	elsif ($aName eq "verbose")
	{
		SIGNALduino_Log3 $name, 3, "$name: setting Verbose to: " . $aVal;
		$hash->{unknownmessages}="" if $aVal <4;
		
	}
	elsif ($aName eq "debug")
	{
		$debug = $aVal;
		SIGNALduino_Log3 $name, 3, "$name: setting debug to: " . $debug;
	}
	elsif ($aName eq "whitelist_IDs")
	{
		SIGNALduino_Log3 $name, 3, "$name Attr: whitelist_IDs";
		if ($init_done) {		# beim fhem Start wird das SIGNALduino_IdList nicht aufgerufen, da es beim define aufgerufen wird
			SIGNALduino_IdList("x:$name",$aVal);
		}
	}
	elsif ($aName eq "blacklist_IDs")
	{
		SIGNALduino_Log3 $name, 3, "$name Attr: blacklist_IDs";
		if ($init_done) {		# beim fhem Start wird das SIGNALduino_IdList nicht aufgerufen, da es beim define aufgerufen wird
			SIGNALduino_IdList("x:$name",undef,$aVal);
		}
	}
	elsif ($aName eq "development")
	{
		SIGNALduino_Log3 $name, 3, "$name Attr: development";
		if ($init_done) {		# beim fhem Start wird das SIGNALduino_IdList nicht aufgerufen, da es beim define aufgerufen wird
			SIGNALduino_IdList("x:$name",undef,undef,$aVal);
		}
	}
	elsif ($aName eq "doubleMsgCheck_IDs")
	{
		if (defined($aVal)) {
			if (length($aVal)>0) {
				if (substr($aVal,0 ,1) eq '#') {
					SIGNALduino_Log3 $name, 3, "$name Attr: doubleMsgCheck_IDs disabled: $aVal";
					delete $hash->{DoubleMsgIDs};
				}
				else {
					SIGNALduino_Log3 $name, 3, "$name Attr: doubleMsgCheck_IDs enabled: $aVal";
					my %DoubleMsgiD = map { $_ => 1 } split(",", $aVal);
					$hash->{DoubleMsgIDs} = \%DoubleMsgiD;
					#print Dumper $hash->{DoubleMsgIDs};
				}
			}
			else {
				SIGNALduino_Log3 $name, 3, "$name delete Attr: doubleMsgCheck_IDs";
				delete $hash->{DoubleMsgIDs};
			}
		}
	}
	elsif ($aName eq "cc1101_frequency")
	{
		if ($aVal eq "" || $aVal < 800) {
			SIGNALduino_Log3 $name, 3, "$name: delete cc1101_frequeny";
			delete ($hash->{cc1101_frequency}) if (defined($hash->{cc1101_frequency}));
		} else {
			SIGNALduino_Log3 $name, 3, "$name: setting cc1101_frequency to 868";
			$hash->{cc1101_frequency} = 868;
		}
	}
	
  	return undef;
}


sub SIGNALduino_IdList($@)
{
	my ($param, $aVal, $blacklist, $develop) = @_;
	my (undef,$name) = split(':', $param);
	my $hash = $defs{$name};

	my @msIdList = ();
	my @muIdList = ();
	my @mcIdList = ();

	if (!defined($aVal)) {
		$aVal = AttrVal($name,"whitelist_IDs","");
	}
	SIGNALduino_Log3 $name, 3, "$name IdList: whitelistIds=$aVal" if ($aVal);
	
	if (!defined($blacklist)) {
		$blacklist = AttrVal($name,"blacklist_IDs","");
	}
	SIGNALduino_Log3 $name, 3, "$name IdList: blacklistIds=$blacklist" if ($blacklist);
	
	if (!defined($develop)) {
		$develop = AttrVal($name,"development","");
	}
	$develop = lc($develop);
	SIGNALduino_Log3 $name, 3, "$name IdList: development=$develop" if ($develop);

	my %WhitelistIDs;
	my %BlacklistIDs;
	my $wflag = 0;		# whitelist flag, 0=disabled
	my $bflag = 0;		# blacklist flag, 0=disabled
	if (defined($aVal) && length($aVal)>0)
	{
		if (substr($aVal,0 ,1) eq '#') {
			SIGNALduino_Log3 $name, 3, "$name IdList, Attr whitelist disabled: $aVal";
		}
		else {
			%WhitelistIDs = map { $_ => 1 } split(",", $aVal);
			#my $w = join ', ' => map "$_" => keys %WhitelistIDs;
			#SIGNALduino_Log3 $name, 3, "Attr whitelist $w";
			$wflag = 1;
		}
	}
	if ($wflag == 0) {		# whitelist disabled
		if (defined($blacklist) && length($blacklist)>0) {
			%BlacklistIDs = map { $_ => 1 } split(",", $blacklist);
			my $w = join ', ' => map "$_" => keys %BlacklistIDs;
			SIGNALduino_Log3 $name, 3, "$name IdList, Attr blacklist $w";
			$bflag = 1;
		}
	}
	
	my $id;
	my $devid;
	my $wIdFound;
	foreach $id (keys %ProtocolListSIGNALduino)
	{
		next if ($id eq 'id');
		$wIdFound = 0;
		
		if ($wflag == 1)				# whitelist
		{
			if (defined($WhitelistIDs{$id}))	# Id wurde in der whitelist gefunden
			{
				$wIdFound = 1;
			}
			else
			{
				#Log3 $name, 3, "skip ID $id";
				next;
			}
		}
		
		if ($wIdFound == 0)	# wenn die Id in der whitelist gefunden wurde, dann die folgenden Abfragen ueberspringen
		{
			if ($bflag == 1 && defined($BlacklistIDs{$id})) {
				SIGNALduino_Log3 $name, 3, "$name IdList, skip Blacklist ID $id";
				next;
			}
		
			if (defined($ProtocolListSIGNALduino{$id}{developId}) && substr($ProtocolListSIGNALduino{$id}{developId},0,1) eq "p") {
				$devid = "p$id";
				if ($develop !~ m/$devid/) {						# skip wenn die Id nicht im Attribut development steht
					SIGNALduino_Log3 $name, 3, "$name IdList: ID=$devid skiped (developId=p)";
					next;
				}
			}
		
			if (defined($ProtocolListSIGNALduino{$id}{developId}) && substr($ProtocolListSIGNALduino{$id}{developId},0,1) eq "y") {
				$devid = "p$id";
				if (($develop !~ m/y/) && ($develop !~ m/$devid/)) {			# skip wenn y nicht im Attribut development steht
					SIGNALduino_Log3 $name, 3, "$name: IdList ID=$id skiped (developId=y)";
					next;
				}
			}
		}
		
		if (exists ($ProtocolListSIGNALduino{$id}{format}) && $ProtocolListSIGNALduino{$id}{format} eq "manchester")
		{
			push (@mcIdList, $id);
		} 
		elsif (exists $ProtocolListSIGNALduino{$id}{sync})
		{
			push (@msIdList, $id);
		}
		elsif (exists ($ProtocolListSIGNALduino{$id}{clockabs}))
		{
			push (@muIdList, $id);
		}
	}

	@msIdList = sort {$a <=> $b} @msIdList;
	@muIdList = sort {$a <=> $b} @muIdList;
	@mcIdList = sort {$a <=> $b} @mcIdList;

	SIGNALduino_Log3 $name, 3, "$name: IDlist MS @msIdList";
	SIGNALduino_Log3 $name, 3, "$name: IDlist MU @muIdList";
    SIGNALduino_Log3 $name, 3, "$name: IDlist MC @mcIdList";
	
	$hash->{msIdList} = \@msIdList;
    $hash->{muIdList} = \@muIdList;
    $hash->{mcIdList} = \@mcIdList;
}


sub SIGNALduino_callsub
{
	my $funcname =shift;
	my $method = shift;
	my $name = shift;
	my @args = @_;
	
	
	if ( defined $method && defined &$method )   
	{
		#my $subname = @{[eval {&$method}, $@ =~ /.*/]};
		SIGNALduino_Log3 $name, 5, "$name: applying $funcname, value before: @args"; # method $subname";
		
		my ($rcode, @returnvalues) = $method->($name, @args) ;	
			
		if (@returnvalues && defined($returnvalues[0])) {
			SIGNALduino_Log3 $name, 5, "$name: rcode=$rcode, modified value after $funcname: @returnvalues";
		} else {
	   		SIGNALduino_Log3 $name, 5, "$name: rcode=$rcode, after calling $funcname";
	    } 
	    return ($rcode, @returnvalues);
	} elsif (defined $method ) {					
		SIGNALduino_Log3 $name, 5, "$name: Error: Unknown method $funcname Please check definition";
		return (0,undef);
	}	
	return (1,@args);			
}


# calculates the hex (in bits) and adds it at the beginning of the message
# input = @list
# output = @list
sub SIGNALduino_lengtnPrefix
{
	my ($name, @bit_msg) = @_;
	
	my $msg = join("",@bit_msg);	

	#$msg = unpack("B8", pack("N", length($msg))).$msg;
	$msg=sprintf('%08b', length($msg)).$msg;
	
	return (1,split("",$msg));
}


sub SIGNALduino_PreparingSend_FS20_FHT($$$) {
	my ($id, $sum, $msg) = @_;
	my $temp = 0;
	my $newmsg = "P$id#0000000000001";	  # 12 Bit Praeambel, 1 bit
	
	for (my $i=0; $i<length($msg); $i+=2) {
		$temp = hex(substr($msg, $i, 2));
		$sum += $temp;
		$newmsg .= SIGNALduino_dec2binppari($temp);
	}
	
	$newmsg .= SIGNALduino_dec2binppari($sum & 0xFF);   # Checksum
	my $repeats = $id - 71;			# FS20(74)=3, FHT(73)=2
	$newmsg .= "0P#R" . $repeats;		# EOT, Pause, 3 Repeats    
	
	return $newmsg;
}

sub SIGNALduino_dec2binppari {      # dec to bin . parity
	my $num = shift;
	my $parity = 0;
	my $nbin = sprintf("%08b",$num);
	foreach my $c (split //, $nbin) {
		$parity ^= $c;
	}
	my $result = $nbin . $parity;		# bin(num) . paritybit
	return $result;
}


sub SIGNALduino_bit2Arctec
{
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);	
	# Convert 0 -> 01   1 -> 10 to be compatible with IT Module
	$msg =~ s/0/z/g;
	$msg =~ s/1/10/g;
	$msg =~ s/z/01/g;
	return (1,split("",$msg)); 
}

sub SIGNALduino_bit2itv1
{
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);	

#	$msg =~ s/0F/01/g;		# Convert 0F -> 01 (F) to be compatible with CUL
	$msg =~ s/0F/11/g;		# Convert 0F -> 11 (1) float
	if (index($msg,'F') == -1) {
		return (1,split("",$msg));
	} else {
		return (0,0);
	}
}


sub SIGNALduino_ITV1_tristateToBit($)
{
	my ($msg) = @_;
	# Convert 0 -> 00   1 -> 11 F => 01 to be compatible with IT Module
	$msg =~ s/0/00/g;
	$msg =~ s/1/11/g;
	$msg =~ s/F/01/g;
	$msg =~ s/D/10/g;
		
	return (1,$msg);
}

sub SIGNALduino_ITV1_31_tristateToBit($)	# ID 3.1
{
	my ($msg) = @_;
	# Convert 0 -> 00   1 -> 0D F => 01 to be compatible with IT Module
	$msg =~ s/0/00/g;
	$msg =~ s/1/0D/g;
	$msg =~ s/F/01/g;
		
	return (1,$msg);
}

sub SIGNALduino_HE800($@)
{
	my ($name, @bit_msg) = @_;
	my $protolength = scalar @bit_msg;
	
	if ($protolength < 40) {
		for (my $i=0; $i<(40-$protolength); $i++) {
			push(@bit_msg, 0);
		}
	}
	return (1,@bit_msg);
}

sub SIGNALduino_HE_EU($@)
{
	my ($name, @bit_msg) = @_;
	my $protolength = scalar @bit_msg;
	
	if ($protolength < 72) {
		for (my $i=0; $i<(72-$protolength); $i++) {
			push(@bit_msg, 0);
		}
	}
	return (1,@bit_msg);
}

sub SIGNALduino_postDemo_Hoermann($@) {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);
	
	if (substr($msg,0,9) ne "000000001") {		# check ident
		SIGNALduino_Log3 $name, 4, "$name: Hoermann ERROR - Ident not 000000001";
		return 0, undef;
	} else {
		SIGNALduino_Log3 $name, 5, "$name: Hoermann $msg";
		$msg = substr($msg,9);
		return (1,split("",$msg));
	}
}

sub SIGNALduino_postDemo_EM($@) {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);
	my $msg_start = index($msg, "0000000001");				# find start
	my $count;
	$msg = substr($msg,$msg_start + 10);						# delete preamble + 1 bit
	my $new_msg = "";
	my $crcbyte;
	my $msgcrc = 0;

	if ($msg_start > 0 && length $msg == 89) {
		for ($count = 0; $count < length ($msg) ; $count +=9) {
			$crcbyte = substr($msg,$count,8);
			if ($count < (length($msg) - 10)) {
				$new_msg.= join "", reverse @bit_msg[$msg_start + 10 + $count.. $msg_start + 17 + $count];
				$msgcrc = $msgcrc ^ oct( "0b$crcbyte" );
			}
		}
	
		if ($msgcrc == oct( "0b$crcbyte" )) {
			SIGNALduino_Log3 $name, 4, "$name: EM Protocol - CRC OK";
			return (1,split("",$new_msg));
		} else {
			SIGNALduino_Log3 $name, 3, "$name: EM Protocol - CRC ERROR";
			return 0, undef;
		}
	}
	
	SIGNALduino_Log3 $name, 3, "$name: EM Protocol - Start not found or length msg (".length $msg.") not correct";
	return 0, undef;
}

sub SIGNALduino_postDemo_FS20($@) {
	my ($name, @bit_msg) = @_;
	my $datastart = 0;
   my $protolength = scalar @bit_msg;
	my $sum = 6;
	my $b = 0;
	my $i = 0;
   for ($datastart = 0; $datastart < $protolength; $datastart++) {   # Start bei erstem Bit mit Wert 1 suchen
      last if $bit_msg[$datastart] eq "1";
   }
   if ($datastart == $protolength) {                                 # all bits are 0
		SIGNALduino_Log3 $name, 4, "$name: FS20 - ERROR message all bit are zeros";
		return 0, undef;
   }
   splice(@bit_msg, 0, $datastart + 1);                             	# delete preamble + 1 bit
   $protolength = scalar @bit_msg;
   SIGNALduino_Log3 $name, 5, "$name: FS20 - pos=$datastart length=$protolength";
   if ($protolength == 46 || $protolength == 55) {			# If it 1 bit too long, then it will be removed (EOT-Bit)
      pop(@bit_msg);
      $protolength--;
   }
   if ($protolength == 45 || $protolength == 54) {          ### FS20 length 45 or 54
      for(my $b = 0; $b < $protolength - 9; $b += 9) {	                  # build sum over first 4 or 5 bytes
         $sum += oct( "0b".(join "", @bit_msg[$b .. $b + 7]));
      }
      my $checksum = oct( "0b".(join "", @bit_msg[$protolength - 9 .. $protolength - 2]));   # Checksum Byte 5 or 6
      if ((($sum + 6) & 0xFF) == $checksum) {			# Message from FHT80 roothermostat
         SIGNALduino_Log3 $name, 5, "$name: FS20 - Detection aborted, checksum matches FHT code";
         return 0, undef;
      }
      if (($sum & 0xFF) == $checksum) {				            ## FH20 remote control
			for(my $b = 0; $b < $protolength; $b += 9) {	            # check parity over 5 or 6 bytes
				my $parity = 0;					                                 # Parity even
				for(my $i = $b; $i < $b + 9; $i++) {			                  # Parity over 1 byte + 1 bit
					$parity += $bit_msg[$i];
				}
				if ($parity % 2 != 0) {
					SIGNALduino_Log3 $name, 4, "$name: FS20 ERROR - Parity not even";
					return 0, undef;
				}
			}																						# parity ok
			for(my $b = $protolength - 1; $b > 0; $b -= 9) {	               # delete 5 or 6 parity bits
				splice(@bit_msg, $b, 1);
			}
         if ($protolength == 45) {                       		### FS20 length 45
            splice(@bit_msg, 32, 8);                                       # delete checksum
            splice(@bit_msg, 24, 0, (0,0,0,0,0,0,0,0));                    # insert Byte 3
         } else {                                              ### FS20 length 54
            splice(@bit_msg, 40, 8);                                       # delete checksum
         }
			my $dmsg = SIGNALduino_b2h(join "", @bit_msg);
			SIGNALduino_Log3 $name, 4, "$name: FS20 - remote control post demodulation $dmsg length $protolength";
			return (1, @bit_msg);											## FHT80TF ok
      }
      else {
         SIGNALduino_Log3 $name, 4, "$name: FS20 ERROR - wrong checksum";
      }
   }
   else {
      SIGNALduino_Log3 $name, 5, "$name: FS20 ERROR - wrong length=$protolength (must be 45 or 54)";
   }
   return 0, undef;
}

sub SIGNALduino_postDemo_FHT80($@) {
	my ($name, @bit_msg) = @_;
	my $datastart = 0;
   my $protolength = scalar @bit_msg;
	my $sum = 12;
	my $b = 0;
	my $i = 0;
   for ($datastart = 0; $datastart < $protolength; $datastart++) {   # Start bei erstem Bit mit Wert 1 suchen
      last if $bit_msg[$datastart] eq "1";
   }
   if ($datastart == $protolength) {                                 # all bits are 0
		SIGNALduino_Log3 $name, 4, "$name: FHT80 - ERROR message all bit are zeros";
		return 0, undef;
   }
   splice(@bit_msg, 0, $datastart + 1);                             	# delete preamble + 1 bit
   $protolength = scalar @bit_msg;
   SIGNALduino_Log3 $name, 5, "$name: FHT80 - pos=$datastart length=$protolength";
   if ($protolength == 55) {						# If it 1 bit too long, then it will be removed (EOT-Bit)
      pop(@bit_msg);
      $protolength--;
   }
   if ($protolength == 54) {                       		### FHT80 fixed length
      for($b = 0; $b < 45; $b += 9) {	                             # build sum over first 5 bytes
         $sum += oct( "0b".(join "", @bit_msg[$b .. $b + 7]));
      }
      my $checksum = oct( "0b".(join "", @bit_msg[45 .. 52]));          # Checksum Byte 6
      if ((($sum - 6) & 0xFF) == $checksum) {		## Message from FS20 remote control
         SIGNALduino_Log3 $name, 5, "$name: FHT80 - Detection aborted, checksum matches FS20 code";
         return 0, undef;
      }
      if (($sum & 0xFF) == $checksum) {								## FHT80 Raumthermostat
         for($b = 0; $b < 54; $b += 9) {	                              # check parity over 6 byte
            my $parity = 0;					                              # Parity even
            for($i = $b; $i < $b + 9; $i++) {			                  # Parity over 1 byte + 1 bit
               $parity += $bit_msg[$i];
            }
            if ($parity % 2 != 0) {
               SIGNALduino_Log3 $name, 4, "$name: FHT80 ERROR - Parity not even";
               return 0, undef;
            }
         }																					# parity ok
         for($b = 53; $b > 0; $b -= 9) {	                              # delete 6 parity bits
            splice(@bit_msg, $b, 1);
         }
         if ($bit_msg[26] != 1) {                                       # Bit 5 Byte 3 must 1
            SIGNALduino_Log3 $name, 4, "$name: FHT80 ERROR - byte 3 bit 5 not 1";
            return 0, undef;
         }
         splice(@bit_msg, 40, 8);                                       # delete checksum
         splice(@bit_msg, 24, 0, (0,0,0,0,0,0,0,0));# insert Byte 3
         my $dmsg = SIGNALduino_b2h(join "", @bit_msg);
         SIGNALduino_Log3 $name, 4, "$name: FHT80 - roomthermostat post demodulation $dmsg";
         return (1, @bit_msg);											## FHT80 ok
      }
      else {
         SIGNALduino_Log3 $name, 4, "$name: FHT80 ERROR - wrong checksum";
      }
   }
   else {
      SIGNALduino_Log3 $name, 5, "$name: FHT80 ERROR - wrong length=$protolength (must be 54)";
   }
   return 0, undef;
}

sub SIGNALduino_postDemo_FHT80TF($@) {
	my ($name, @bit_msg) = @_;
	my $datastart = 0;
   my $protolength = scalar @bit_msg;
	my $sum = 12;			
	my $b = 0;
   if ($protolength < 46) {                                        	# min 5 bytes + 6 bits
		SIGNALduino_Log3 $name, 4, "$name: FHT80TF - ERROR lenght of message < 46";
		return 0, undef;
   }
   for ($datastart = 0; $datastart < $protolength; $datastart++) {   # Start bei erstem Bit mit Wert 1 suchen
      last if $bit_msg[$datastart] eq "1";
   }
   if ($datastart == $protolength) {                                 # all bits are 0
		SIGNALduino_Log3 $name, 4, "$name: FHT80TF - ERROR message all bit are zeros";
		return 0, undef;
   }
   splice(@bit_msg, 0, $datastart + 1);                             	# delete preamble + 1 bit
   $protolength = scalar @bit_msg;
   if ($protolength == 45) {                       		      ### FHT80TF fixed length
      for(my $b = 0; $b < 36; $b += 9) {	                             # build sum over first 4 bytes
         $sum += oct( "0b".(join "", @bit_msg[$b .. $b + 7]));
      }
      my $checksum = oct( "0b".(join "", @bit_msg[36 .. 43]));          # Checksum Byte 5
      if (($sum & 0xFF) == $checksum) {									## FHT80TF Tuer-/Fensterkontakt
			for(my $b = 0; $b < 45; $b += 9) {	                           # check parity over 5 byte
				my $parity = 0;					                              # Parity even
				for(my $i = $b; $i < $b + 9; $i++) {			               # Parity over 1 byte + 1 bit
					$parity += $bit_msg[$i];
				}
				if ($parity % 2 != 0) {
					SIGNALduino_Log3 $name, 4, "$name: FHT80TF ERROR - Parity not even";
					return 0, undef;
				}
			}																					# parity ok
			for(my $b = 44; $b > 0; $b -= 9) {	                           # delete 5 parity bits
				splice(@bit_msg, $b, 1);
			}
         if ($bit_msg[26] != 0) {                                       # Bit 5 Byte 3 must 0
            SIGNALduino_Log3 $name, 4, "$name: FHT80TF ERROR - byte 3 bit 5 not 0";
            return 0, undef;
         }
			splice(@bit_msg, 32, 8);                                       # delete checksum
				my $dmsg = SIGNALduino_b2h(join "", @bit_msg);
				SIGNALduino_Log3 $name, 4, "$name: FHT80TF - door/window switch post demodulation $dmsg";
			return (1, @bit_msg);											## FHT80TF ok
      } 
   } 
   return 0, undef;
}

sub SIGNALduino_postDemo_WS7035($@) {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);
	my $parity = 0;					# Parity even

	SIGNALduino_Log3 $name, 4, "$name: WS7035 $msg";
	if (substr($msg,0,8) ne "10100000") {		# check ident
		SIGNALduino_Log3 $name, 4, "$name: WS7035 ERROR - Ident not 1010 0000";
		return 0, undef;
	} else {
		for(my $i = 15; $i < 28; $i++) {			# Parity over bit 15 and 12 bit temperature
	      $parity += substr($msg, $i, 1);
		}
		if ($parity % 2 != 0) {
			SIGNALduino_Log3 $name, 4, "$name: WS7035 ERROR - Parity not even";
			return 0, undef;
		} else {
			SIGNALduino_Log3 $name, 4, "$name: WS7035 " . substr($msg,0,4) ." ". substr($msg,4,4) ." ". substr($msg,8,4) ." ". substr($msg,12,4) ." ". substr($msg,16,4) ." ". substr($msg,20,4) ." ". substr($msg,24,4) ." ". substr($msg,28,4) ." ". substr($msg,32,4) ." ". substr($msg,36,4) ." ". substr($msg,40);
			substr($msg, 27, 4, '');			# delete nibble 8
			return (1,split("",$msg));
		}
	}
}

sub SIGNALduino_postDemo_WS2000($@) {
	my ($name, @bit_msg) = @_;
	my $debug = AttrVal($name,"debug",0);
	my @new_bit_msg = "";
	my $protolength = scalar @bit_msg;
	my @datalenghtws = (35,50,35,50,70,40,40,85);
	my $datastart = 0;
	my $datalength = 0;
	my $datalength1 = 0;
	my $index = 0;
	my $data = 0;
	my $dataindex = 0;
	my $error = 0;
	my $check = 0;
	my $sum = 5;
	my $typ = 0;
	my $adr = 0;
	my @sensors = (
		"Thermo",
		"Thermo/Hygro",
		"Rain",
		"Wind",
		"Thermo/Hygro/Baro",
		"Brightness",
		"Pyrano",
		"Kombi"
		);

	for ($datastart = 0; $datastart < $protolength; $datastart++) {   # Start bei erstem Bit mit Wert 1 suchen
		last if $bit_msg[$datastart] eq "1";
	}
	if ($datastart == $protolength) {                                 # all bits are 0
		SIGNALduino_Log3 $name, 4, "$name: WS2000 - ERROR message all bit are zeros";
		return 0, undef;
	}
	$datalength = $protolength - $datastart;
	$datalength1 = $datalength - ($datalength % 5);  		# modulo 5
	SIGNALduino_Log3 $name, 5, "$name: WS2000 protolength: $protolength, datastart: $datastart, datalength $datalength";
	$typ = oct( "0b".(join "", reverse @bit_msg[$datastart + 1.. $datastart + 4]));		# Sensortyp
	if ($typ > 7) {
		SIGNALduino_Log3 $name, 4, "$name: WS2000 Sensortyp $typ - ERROR typ to big";
		return 0, undef;
	}
	if ($typ == 1 && ($datalength == 45 || $datalength == 46)) {$datalength1 += 5;}		# Typ 1 ohne Summe
	if ($datalenghtws[$typ] != $datalength1) {												# check lenght of message
		SIGNALduino_Log3 $name, 4, "$name: WS2000 Sensortyp $typ - ERROR lenght of message $datalength1 ($datalenghtws[$typ])";
		return 0, undef;
	} elsif ($datastart > 10) {									# max 10 Bit preamble
		SIGNALduino_Log3 $name, 4, "$name: WS2000 ERROR preamble > 10 ($datastart)";
		return 0, undef;
	} else {
		do {
			$error += !$bit_msg[$index + $datastart];			# jedes 5. Bit muss 1 sein
			$dataindex = $index + $datastart + 1;				 
			$data = oct( "0b".(join "", reverse @bit_msg[$dataindex .. $dataindex + 3]));
			if ($index == 5) {$adr = ($data & 0x07)}			# Sensoradresse
			if ($datalength == 45 || $datalength == 46) { 	# Typ 1 ohne Summe
				if ($index <= $datalength - 5) {
					$check = $check ^ $data;		# Check - Typ XOR Adresse XOR  bis XOR Check muss 0 ergeben
				}
			} else {
				if ($index <= $datalength - 10) {
					$check = $check ^ $data;		# Check - Typ XOR Adresse XOR  bis XOR Check muss 0 ergeben
					$sum += $data;
				}
			}
			$index += 5;
		} until ($index >= $datalength -1 );
	}
	if ($error != 0) {
		SIGNALduino_Log3 $name, 4, "$name: WS2000 Sensortyp $typ Adr $adr - ERROR examination bit";
		return (0, undef);
	} elsif ($check != 0) {
		SIGNALduino_Log3 $name, 4, "$name: WS2000 Sensortyp $typ Adr $adr - ERROR check XOR";
		return (0, undef);
	} else {
		if ($datalength < 45 || $datalength > 46) { 			# Summe pruefen, ausser Typ 1 ohne Summe
			$data = oct( "0b".(join "", reverse @bit_msg[$dataindex .. $dataindex + 3]));
			if ($data != ($sum & 0x0F)) {
				SIGNALduino_Log3 $name, 4, "$name: WS2000 Sensortyp $typ Adr $adr - ERROR sum";
				return (0, undef);
			}
		}
		SIGNALduino_Log3 $name, 4, "$name: WS2000 Sensortyp $typ Adr $adr - $sensors[$typ]";
		$datastart += 1;																							# [x] - 14_CUL_WS
		@new_bit_msg[4 .. 7] = reverse @bit_msg[$datastart .. $datastart+3];						# [2]  Sensortyp
		@new_bit_msg[0 .. 3] = reverse @bit_msg[$datastart+5 .. $datastart+8];					# [1]  Sensoradresse
		@new_bit_msg[12 .. 15] = reverse @bit_msg[$datastart+10 .. $datastart+13];				# [4]  T 0.1, R LSN, Wi 0.1, B   1, Py   1
		@new_bit_msg[8 .. 11] = reverse @bit_msg[$datastart+15 .. $datastart+18];				# [3]  T   1, R MID, Wi   1, B  10, Py  10
		if ($typ == 0 || $typ == 2) {		# Thermo (AS3), Rain (S2000R, WS7000-16)
			@new_bit_msg[16 .. 19] = reverse @bit_msg[$datastart+20 .. $datastart+23];			# [5]  T  10, R MSN
		} else {
			@new_bit_msg[20 .. 23] = reverse @bit_msg[$datastart+20 .. $datastart+23];			# [6]  T  10, 			Wi  10, B 100, Py 100
			@new_bit_msg[16 .. 19] = reverse @bit_msg[$datastart+25 .. $datastart+28];			# [5]  H 0.1, 			Wr   1, B Fak, Py Fak
			if ($typ == 1 || $typ == 3 || $typ == 4 || $typ == 7) {	# Thermo/Hygro, Wind, Thermo/Hygro/Baro, Kombi
				@new_bit_msg[28 .. 31] = reverse @bit_msg[$datastart+30 .. $datastart+33];		# [8]  H   1,			Wr  10
				@new_bit_msg[24 .. 27] = reverse @bit_msg[$datastart+35 .. $datastart+38];		# [7]  H  10,			Wr 100
				if ($typ == 4) {	# Thermo/Hygro/Baro (S2001I, S2001ID)
					@new_bit_msg[36 .. 39] = reverse @bit_msg[$datastart+40 .. $datastart+43];	# [10] P    1
					@new_bit_msg[32 .. 35] = reverse @bit_msg[$datastart+45 .. $datastart+48];	# [9]  P   10
					@new_bit_msg[44 .. 47] = reverse @bit_msg[$datastart+50 .. $datastart+53];	# [12] P  100
					@new_bit_msg[40 .. 43] = reverse @bit_msg[$datastart+55 .. $datastart+58];	# [11] P Null
				}
			}
		}
		return (1, @new_bit_msg);
	}

}


sub SIGNALduino_postDemo_WS7053($@) {
	my ($name, @bit_msg) = @_;
	my $msg = join("",@bit_msg);
	my $parity = 0;	                       # Parity even
	SIGNALduino_Log3 $name, 4, "$name: WS7053 - MSG = $msg";
	my $msg_start = index($msg, "10100000");
	if ($msg_start > 0) {                  # start not correct
		$msg = substr($msg, $msg_start);
		$msg .= "0";
		SIGNALduino_Log3 $name, 5, "$name: WS7053 - cut $msg_start char(s) at begin";
	}
	if ($msg_start < 0) {                  # start not found
		SIGNALduino_Log3 $name, 3, "$name: WS7053 ERROR - Ident 10100000 not found";
		return 0, undef;
	} else {
		if (length($msg) < 32) {             # msg too short
			SIGNALduino_Log3 $name, 3, "$name: WS7053 ERROR - msg too short, length " . length($msg);
		return 0, undef;
		} else {
			for(my $i = 15; $i < 28; $i++) {   # Parity over bit 15 and 12 bit temperature
				$parity += substr($msg, $i, 1);
			}
			if ($parity % 2 != 0) {
				SIGNALduino_Log3 $name, 3, "$name: WS7053 ERROR - Parity not even";
				return 0, undef;
			} else {
				SIGNALduino_Log3 $name, 5, "$name: WS7053 before: " . substr($msg,0,4) ." ". substr($msg,4,4) ." ". substr($msg,8,4) ." ". substr($msg,12,4) ." ". substr($msg,16,4) ." ". substr($msg,20,4) ." ". substr($msg,24,4) ." ". substr($msg,28,4);
				# Format from 7053:  Bit 0-7 Ident, Bit 8-15 Rolling Code/Parity, Bit 16-27 Temperature (12.3), Bit 28-31 Zero
				my $new_msg = substr($msg,0,28) . substr($msg,16,8) . substr($msg,28,4);
				# Format for CUL_TX: Bit 0-7 Ident, Bit 8-15 Rolling Code/Parity, Bit 16-27 Temperature (12.3), Bit 28 - 35 Temperature (12), Bit 36-39 Zero
				SIGNALduino_Log3 $name, 5, "$name: WS7053 after:  " . substr($new_msg,0,4) ." ". substr($new_msg,4,4) ." ". substr($new_msg,8,4) ." ". substr($new_msg,12,4) ." ". substr($new_msg,16,4) ." ". substr($new_msg,20,4) ." ". substr($new_msg,24,4) ." ". substr($new_msg,28,4) ." ". substr($new_msg,32,4) ." ". substr($new_msg,36,4);
				return (1,split("",$new_msg));
			}
		}
	}
}


# manchester method

sub SIGNALduino_MCTFA
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	
	my $preamble_pos;
	my $message_end;
	my $message_length;
		
	#if ($bitData =~ m/^.?(1){16,24}0101/)  {  
	if ($bitData =~ m/(1{10}101)/ )
	{ 
		$preamble_pos=$+[1];
		SIGNALduino_Log3 $name, 4, "$name: TFA 30.3208.0 preamble_pos = $preamble_pos";
		return return (-1," sync not found") if ($preamble_pos <=0);
		my @messages;
		
		do 
		{
			$message_end = index($bitData,"1111111111101",$preamble_pos); 
			if ($message_end < $preamble_pos)
			{
				$message_end=length($bitData);
			} 
			$message_length = ($message_end - $preamble_pos);			
			
			my $part_str=substr($bitData,$preamble_pos,$message_length);
			$part_str = substr($part_str,0,52) if (length($part_str)) > 52;

			SIGNALduino_Log3 $name, 4, "$name: TFA message start=$preamble_pos end=$message_end with length".$message_length;
			SIGNALduino_Log3 $name, 5, "$name: part $part_str";
			my $hex=SIGNALduino_b2h($part_str);
			push (@messages,$hex);
			SIGNALduino_Log3 $name, 4, "$name: ".$hex;
			$preamble_pos=index($bitData,"1101",$message_end)+4;
		}  while ( $message_end < length($bitData) );
		
		my %seen;
		my @dupmessages = map { 1==$seen{$_}++ ? $_ : () } @messages;
	
		if (scalar(@dupmessages) > 0 ) {
			SIGNALduino_Log3 $name, 4, "$name: repeated hex ".$dupmessages[0]." found ".$seen{$dupmessages[0]}." times";
			return  (1,$dupmessages[0]);
		} else {  
			return (-1," no duplicate found");
		}
	}
	return (-1,undef);
	
}


sub SIGNALduino_OSV2()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	
	my $preamble_pos;
	my $message_end;
	my $message_length;
	
	#$bitData =~ tr/10/01/;
       #if ($bitData =~ m/^.?(01){12,17}.?10011001/) 
	if ($bitData =~ m/^.?(01){8,17}.?10011001/) 
	{  # Valid OSV2 detected!	
		#$preamble_pos=index($bitData,"10011001",24);
		$preamble_pos=$+[1];
		
		SIGNALduino_Log3 $name, 4, "$name: OSV2 protocol detected: preamble_pos = $preamble_pos";
		return return (-1," sync not found") if ($preamble_pos <=18);
		
		$message_end=$-[1] if ($bitData =~ m/^.{44,}(01){16,17}.?10011001/); #Todo regex .{44,} 44 should be calculated from $preamble_pos+ min message lengh (44)
		if (!defined($message_end) || $message_end < $preamble_pos) {
			$message_end = length($bitData);
		} else {
			$message_end += 16;
			SIGNALduino_Log3 $name, 4, "$name: OSV2 message end pattern found at pos $message_end  lengthBitData=".length($bitData);
		}
		$message_length = ($message_end - $preamble_pos)/2;

		return (-1," message is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $message_length < $ProtocolListSIGNALduino{$id}{length_min} );
		return (-1," message is to long") if (defined($ProtocolListSIGNALduino{$id}{length_max}) && $message_length > $ProtocolListSIGNALduino{$id}{length_max} );
		
		my $idx=0;
		my $osv2bits="";
		my $osv2hex ="";
		
		for ($idx=$preamble_pos;$idx<$message_end;$idx=$idx+16)
		{
			if ($message_end-$idx < 8 )
			{
			  last;
			}
			my $osv2byte = "";
			$osv2byte=NULL;
			$osv2byte=substr($bitData,$idx,16);

			my $rvosv2byte="";
			
			for (my $p=0;$p<length($osv2byte);$p=$p+2)
			{
				$rvosv2byte = substr($osv2byte,$p,1).$rvosv2byte;
			}
			$rvosv2byte =~ tr/10/01/;
			
			if (length($rvosv2byte) eq 8) {
				$osv2hex=$osv2hex.sprintf('%02X', oct("0b$rvosv2byte"))  ;
			} else {
				$osv2hex=$osv2hex.sprintf('%X', oct("0b$rvosv2byte"))  ;
			}
			$osv2bits = $osv2bits.$rvosv2byte;
		}
		$osv2hex = sprintf("%02X", length($osv2hex)*4).$osv2hex;
		SIGNALduino_Log3 $name, 4, "$name: OSV2 protocol converted to hex: ($osv2hex) with length (".(length($osv2hex)*4).") bits";
		#$found=1;
		#$dmsg=$osv2hex;
		return (1,$osv2hex);
	}
	elsif ($bitData =~ m/^.?(1){16,24}0101/)  {  # Valid OSV3 detected!	
		$preamble_pos = index($bitData, '0101', 16);
		$message_end = length($bitData);
		$message_length = $message_end - ($preamble_pos+4);
		SIGNALduino_Log3 $name, 4, "$name: OSV3 protocol detected: preamble_pos = $preamble_pos, message_length = $message_length";
		
		my $idx=0;
		#my $osv3bits="";
		my $osv3hex ="";
		
		for ($idx=$preamble_pos+4;$idx<length($bitData);$idx=$idx+4)
		{
			if (length($bitData)-$idx  < 4 )
			{
			  last;
			}
			my $osv3nibble = "";
			$osv3nibble=NULL;
			$osv3nibble=substr($bitData,$idx,4);

			my $rvosv3nibble="";
			
			for (my $p=0;$p<length($osv3nibble);$p++)
			{
				$rvosv3nibble = substr($osv3nibble,$p,1).$rvosv3nibble;
			}
			$osv3hex=$osv3hex.sprintf('%X', oct("0b$rvosv3nibble"));
			#$osv3bits = $osv3bits.$rvosv3nibble;
		}
		SIGNALduino_Log3 $name, 4, "$name: OSV3 protocol =                     $osv3hex";
		my $korr = 10;
		# Check if nibble 1 is A
		if (substr($osv3hex,1,1) ne 'A')
		{
			my $n1=substr($osv3hex,1,1);
			$korr = hex(substr($osv3hex,3,1));
			substr($osv3hex,1,1,'A');  # nibble 1 = A
			substr($osv3hex,3,1,$n1); # nibble 3 = nibble1
		}
		# Korrektur nibble
		my $insKorr = sprintf('%X', $korr);
		# Check for ending 00
		if (substr($osv3hex,-2,2) eq '00')
		{
			#substr($osv3hex,1,-2);  # remove 00 at end
			$osv3hex = substr($osv3hex, 0, length($osv3hex)-2);
		}
		my $osv3len = length($osv3hex);
		$osv3hex .= '0';
		my $turn0 = substr($osv3hex,5, $osv3len-4);
		my $turn = '';
		for ($idx=0; $idx<$osv3len-5; $idx=$idx+2) {
			$turn = $turn . substr($turn0,$idx+1,1) . substr($turn0,$idx,1);
		}
		$osv3hex = substr($osv3hex,0,5) . $insKorr . $turn;
		$osv3hex = substr($osv3hex,0,$osv3len+1);
		$osv3hex = sprintf("%02X", length($osv3hex)*4).$osv3hex;
		SIGNALduino_Log3 $name, 4, "$name: OSV3 protocol converted to hex: ($osv3hex) with length (".((length($osv3hex)-2)*4).") bits";
		#$found=1;
		#$dmsg=$osv2hex;
		return (1,$osv3hex);
		
	}
	return (-1,undef);
}

sub SIGNALduino_OSV1() {
	my ($name,$bitData,$id,$mcbitnum) = @_;
	return (-1," message is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $mcbitnum < $ProtocolListSIGNALduino{$id}{length_min} );
	return (-1," message is to long") if (defined($ProtocolListSIGNALduino{$id}{length_max}) && $mcbitnum > $ProtocolListSIGNALduino{$id}{length_max} );
	my $calcsum = oct( "0b" . reverse substr($bitData,0,8));
	$calcsum += oct( "0b" . reverse substr($bitData,8,8));
	$calcsum += oct( "0b" . reverse substr($bitData,16,8));
	$calcsum = ($calcsum & 0xFF) + ($calcsum >> 8);
	my $checksum = oct( "0b" . reverse substr($bitData,24,8));
	
	if ($calcsum != $checksum) {	# Checksum
		return (-1,"OSV1 - ERROR checksum not equal: $calcsum != $checksum");
	} 
	#if (substr($bitData,20,1) == 0) {
	#	$bitData =~ tr/01/10/; # invert message and check if it is possible to deocde now
	#} 
	
	SIGNALduino_Log3 $name, 4, "$name: OSV1 input data: $bitData";
	my $newBitData = "00001010";                       # Byte 0:   Id1 = 0x0A
    $newBitData .= "01001101";                         # Byte 1:   Id2 = 0x4D
	my $channel = substr($bitData,6,2);						# Byte 2 h: Channel
	if ($channel == "00") {										# in 0 LSB first
		$newBitData .= "0001";									# out 1 MSB first
	} elsif ($channel == "10") {								# in 4 LSB first
		$newBitData .= "0010";									# out 2 MSB first
	} elsif ($channel == "01") {								# in 4 LSB first
		$newBitData .= "0011";									# out 3 MSB first
	} else {															# in 8 LSB first
		return (-1,"$name: OSV1 - ERROR channel not valid: $channel");
    }
    $newBitData .= "0000";                             # Byte 2 l: ????
    $newBitData .= "0000";                             # Byte 3 h: address
    $newBitData .= reverse substr($bitData,0,4);       # Byte 3 l: address (Rolling Code)
    $newBitData .= reverse substr($bitData,8,4);       # Byte 4 h: T 0,1
    $newBitData .= "0" . substr($bitData,23,1) . "00"; # Byte 4 l: Bit 2 - Batterie 0=ok, 1=low (< 2,5 Volt)
    $newBitData .= reverse substr($bitData,16,4);      # Byte 5 h: T 10
    $newBitData .= reverse substr($bitData,12,4);      # Byte 5 l: T 1
    $newBitData .= "0000";                             # Byte 6 h: immer 0000
    $newBitData .= substr($bitData,21,1) . "000";      # Byte 6 l: Bit 3 - Temperatur 0=pos | 1=neg, Rest 0
    $newBitData .= "00000000";                         # Byte 7: immer 0000 0000
    # calculate new checksum over first 16 nibbles
    $checksum = 0;       
    for (my $i = 0; $i < 64; $i = $i + 4) {
       $checksum += oct( "0b" . substr($newBitData, $i, 4));
    }
    $checksum = ($checksum - 0xa) & 0xff;
    $newBitData .= sprintf("%08b",$checksum);          # Byte 8:   new Checksum 
    $newBitData .= "00000000";                         # Byte 9:   immer 0000 0000
    my $osv1hex = "50" . SIGNALduino_b2h($newBitData); # output with length before
    SIGNALduino_Log3 $name, 4, "$name: OSV1 protocol id $id translated to RFXSensor format";
    SIGNALduino_Log3 $name, 4, "$name: converted to hex: $osv1hex";
    return (1,$osv1hex);
   
}

sub	SIGNALduino_AS()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);
	
	if(index($bitData,"1100",16) >= 0) # $rawData =~ m/^A{2,3}/)
	{  # Valid AS detected!	
		my $message_start = index($bitData,"1100",16);
		Debug "$name: AS protocol detected \n" if ($debug);
		
		my $message_end=index($bitData,"1100",$message_start+16);
		$message_end = length($bitData) if ($message_end == -1);
		my $message_length = $message_end - $message_start;
		
		return (-1," message is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $message_length < $ProtocolListSIGNALduino{$id}{length_min} );
		return (-1," message is to long") if (defined($ProtocolListSIGNALduino{$id}{length_max}) && $message_length > $ProtocolListSIGNALduino{$id}{length_max} );
		
		
		my $msgbits =substr($bitData,$message_start);
		
		my $ashex=sprintf('%02X', oct("0b$msgbits"));
		SIGNALduino_Log3 $name, 5, "$name: AS protocol converted to hex: ($ashex) with length ($message_length) bits \n";

		return (1,$bitData);
	}
	return (-1,undef);
}

sub	SIGNALduino_Hideki()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);
	
	if ($mcbitnum == 89) {
		my $bit0 = substr($bitData,0,1);
		$bit0 = $bit0 ^ 1;
		SIGNALduino_Log3 $name, 4, "$name hideki: L=$mcbitnum add bit $bit0 at begin $bitData";
		$bitData = $bit0 . $bitData;
	}
    Debug "$name: search in $bitData \n" if ($debug);
	my $message_start = index($bitData,"10101110");
	if ($message_start >= 0 )   # 0x75 but in reverse order
	{
		#SIGNALduino_Log3 $name, 3, "$name: receive hideki protocol inverted";
		Debug "$name: Hideki protocol detected \n" if ($debug);

		# Todo: Mindest Laenge fuer startpunkt vorspringen 
		# Todo: Wiederholung auch an das Modul weitergeben, damit es dort geprueft werden kann
		my $message_end = index($bitData,"10101110",$message_start+71); # pruefen auf ein zweites 0x75,  mindestens 72 bit nach 1. 0x75, da der Regensensor minimum 8 Byte besitzt je byte haben wir 9 bit
        $message_end = length($bitData) if ($message_end == -1);
        my $message_length = $message_end - $message_start;
		
		return (-1,"message is to short") if (defined($ProtocolListSIGNALduino{$id}{length_min}) && $message_length < $ProtocolListSIGNALduino{$id}{length_min} );
		return (-1,"message is to long") if (defined($ProtocolListSIGNALduino{$id}{length_max}) && $message_length > $ProtocolListSIGNALduino{$id}{length_max} );

		
		my $hidekihex;
		my $idx;
		
		for ($idx=$message_start; $idx<$message_end; $idx=$idx+9)
		{
			my $byte = "";
			$byte= substr($bitData,$idx,8); ## Ignore every 9th bit
			Debug "$name: byte in order $byte " if ($debug);
			$byte = scalar reverse $byte;
			Debug "$name: byte reversed $byte , as hex: ".sprintf('%X', oct("0b$byte"))."\n" if ($debug);

			$hidekihex=$hidekihex.sprintf('%02X', oct("0b$byte"));
		}
		SIGNALduino_Log3 $name, 4, "$name: hideki protocol converted to hex: $hidekihex with " .$message_length ." bits, messagestart $message_start";

		return  (1,$hidekihex); ## Return only the original bits, include length
	}
	return (-1,"Start pattern (10101110) not found");
}


sub SIGNALduino_Maverick()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);


	if ($bitData =~ m/^.*(101010101001100110010101).*/) 
	{  # Valid Maverick header detected	
		my $header_pos=$+[1];
		
		SIGNALduino_Log3 $name, 4, "$name: Maverick protocol detected: header_pos = $header_pos";

		my $hex=SIGNALduino_b2h(substr($bitData,$header_pos,26*4));
	
		return  (1,$hex); ## Return the bits unchanged in hex
	} else {
		return return (-1," header not found");
	}	
}

sub SIGNALduino_OSPIR()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);


	if ($bitData =~ m/^.*(1{14}|0{14}).*/) 
	{  # Valid Oregon PIR detected	
		my $header_pos=$+[1];
		
		SIGNALduino_Log3 $name, 4, "$name: Oregon PIR protocol detected: header_pos = $header_pos";

		my $hex=SIGNALduino_b2h($bitData);
	
		return  (1,$hex); ## Return the bits unchanged in hex
	} else {
		return return (-1," header not found");
	}	
}
sub SIGNALduino_MCRAW()
{
	my ($name,$bitData,$id,$mcbitnum) = @_;
	my $debug = AttrVal($name,"debug",0);


	my $hex=SIGNALduino_b2h($bitData);
	return  (1,$hex); ## Return the bits unchanged in hex
}



sub SIGNALduino_SomfyRTS()
{
	my ($name, $bitData,$id,$mcbitnum) = @_;
	
    #(my $negBits = $bitData) =~ tr/10/01/;   # Todo: eventuell auf pack umstellen

	if (defined($mcbitnum)) {
		SIGNALduino_Log3 $name, 4, "$name: Somfy bitdata: $bitData ($mcbitnum)";
		if ($mcbitnum == 57) {
			$bitData = substr($bitData, 1, 56);
			SIGNALduino_Log3 $name, 4, "$name: Somfy bitdata: _$bitData (" . length($bitData) . "). Bit am Anfang entfernt";
		}
	}
	my $encData = SIGNALduino_b2h($bitData);

	#SIGNALduino_Log3 $name, 4, "$name: Somfy RTS protocol enc: $encData";
	return (1, $encData);
}

# - - - - - - - - - - - -
#=item SIGNALduino_filterMC()
#This functons, will act as a filter function. It will decode MU data via Manchester encoding
# 
# Will return  $count of ???,  modified $rawData , modified %patternListRaw,
# =cut


sub SIGNALduino_filterMC($$$%)
{
	
	## Warema Implementierung : Todo variabel gestalten
	my ($name,$id,$rawData,%patternListRaw) = @_;
	my $debug = AttrVal($name,"debug",0);
	
	my ($ht, $hasbit, $value) = 0;
	$value=1 if (!$debug);
	my @bitData;
	my @sigData = split "",$rawData;

	foreach my $pulse (@sigData)
	{
	  next if (!defined($patternListRaw{$pulse})); 
	  #SIGNALduino_Log3 $name, 4, "$name: pulese: ".$patternListRaw{$pulse};
		
	  if (SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{clockabs},abs($patternListRaw{$pulse}),$ProtocolListSIGNALduino{$id}{clockabs}*0.5))
	  {
		# Short	
		$hasbit=$ht;
		$ht = $ht ^ 0b00000001;
		$value='S' if($debug);
		#SIGNALduino_Log3 $name, 4, "$name: filter S ";
	  } elsif ( SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{clockabs}*2,abs($patternListRaw{$pulse}),$ProtocolListSIGNALduino{$id}{clockabs}*0.5)) {
	  	# Long
	  	$hasbit=1;
		$ht=1;
		$value='L' if($debug);
		#SIGNALduino_Log3 $name, 4, "$name: filter L ";	
	  } elsif ( SIGNALduino_inTol($ProtocolListSIGNALduino{$id}{syncabs}+(2*$ProtocolListSIGNALduino{$id}{clockabs}),abs($patternListRaw{$pulse}),$ProtocolListSIGNALduino{$id}{clockabs}*0.5))  {
	  	$hasbit=1;
		$ht=1;
		$value='L' if($debug);
	  	#SIGNALduino_Log3 $name, 4, "$name: sync L ";
	
	  } else {
	  	# No Manchester Data
	  	$ht=0;
	  	$hasbit=0;
	  	#SIGNALduino_Log3 $name, 4, "$name: filter n ";
	  }
	  
	  if ($hasbit && $value) {
	  	$value = lc($value) if($debug && $patternListRaw{$pulse} < 0);
	  	my $bit=$patternListRaw{$pulse} > 0 ? 1 : 0;
	  	#SIGNALduino_Log3 $name, 5, "$name: adding value: ".$bit;
	  	
	  	push @bitData, $bit ;
	  }
	}

	my %patternListRawFilter;
	
	$patternListRawFilter{0} = 0;
	$patternListRawFilter{1} = $ProtocolListSIGNALduino{$id}{clockabs};
	
	#SIGNALduino_Log3 $name, 5, "$name: filterbits: ".@bitData;
	$rawData = join "", @bitData;
	return (undef ,$rawData, %patternListRawFilter);
	
}
# - - - - - - - - - - - -
#=item SIGNALduino_filterSign()
#This functons, will act as a filter function. It will remove the sign from the pattern, and compress message and pattern
# 
# Will return  $count of combined values,  modified $rawData , modified %patternListRaw,
# =cut


sub SIGNALduino_filterSign($$$%)
{
	my ($name,$id,$rawData,%patternListRaw) = @_;
	my $debug = AttrVal($name,"debug",0);


	my %buckets;
	# Remove Sign
    %patternListRaw = map { $_ => abs($patternListRaw{$_})} keys %patternListRaw;  ## remove sign from all
    
    my $intol=0;
    my $cnt=0;

    # compress pattern hash
    foreach my $key (keys %patternListRaw) {
			
		#print "chk:".$patternListRaw{$key};
    	#print "\n";

        $intol=0;
		foreach my $b_key (keys %buckets){
			#print "with:".$buckets{$b_key};
			#print "\n";
			
			# $value  - $set <= $tolerance
			if (SIGNALduino_inTol($patternListRaw{$key},$buckets{$b_key},$buckets{$b_key}*0.25))
			{
		    	#print"\t". $patternListRaw{$key}."($key) is intol of ".$buckets{$b_key}."($b_key) \n";
				$cnt++;
				eval "\$rawData =~ tr/$key/$b_key/";

				#if ($key == $msg_parts{clockidx})
				#{
			#		$msg_pats{syncidx} = $buckets{$key};
			#	}
			#	elsif ($key == $msg_parts{syncidx})
			#	{
			#		$msg_pats{syncidx} = $buckets{$key};
			#	}			
				
				$buckets{$b_key} = ($buckets{$b_key} + $patternListRaw{$key}) /2;
				#print"\t recalc to ". $buckets{$b_key}."\n";

				delete ($patternListRaw{$key});  # deletes the compressed entry
				$intol=1;
				last;
			}
		}	
		if ($intol == 0) {
			$buckets{$key}=abs($patternListRaw{$key});
		}
	}

	return ($cnt,$rawData, %patternListRaw);
	#print "rdata: ".$msg_parts{rawData}."\n";

	#print Dumper (%buckets);
	#print Dumper (%msg_parts);

	#modify msg_parts pattern hash
	#$patternListRaw = \%buckets;
}


# - - - - - - - - - - - -
#=item SIGNALduino_compPattern()
#This functons, will act as a filter function. It will remove the sign from the pattern, and compress message and pattern
# 
# Will return  $count of combined values,  modified $rawData , modified %patternListRaw,
# =cut


sub SIGNALduino_compPattern($$$%)
{
	my ($name,$id,$rawData,%patternListRaw) = @_;
	my $debug = AttrVal($name,"debug",0);


	my %buckets;
	# Remove Sign
    #%patternListRaw = map { $_ => abs($patternListRaw{$_})} keys %patternListRaw;  ## remove sing from all
    
    my $intol=0;
    my $cnt=0;

    # compress pattern hash
    foreach my $key (keys %patternListRaw) {
			
		#print "chk:".$patternListRaw{$key};
    	#print "\n";

        $intol=0;
		foreach my $b_key (keys %buckets){
			#print "with:".$buckets{$b_key};
			#print "\n";
			
			# $value  - $set <= $tolerance
			if (SIGNALduino_inTol($patternListRaw{$key},$buckets{$b_key},$buckets{$b_key}*0.4))
			{
		    	#print"\t". $patternListRaw{$key}."($key) is intol of ".$buckets{$b_key}."($b_key) \n";
				$cnt++;
				eval "\$rawData =~ tr/$key/$b_key/";

				#if ($key == $msg_parts{clockidx})
				#{
			#		$msg_pats{syncidx} = $buckets{$key};
			#	}
			#	elsif ($key == $msg_parts{syncidx})
			#	{
			#		$msg_pats{syncidx} = $buckets{$key};
			#	}			
				
				$buckets{$b_key} = ($buckets{$b_key} + $patternListRaw{$key}) /2;
				#print"\t recalc to ". $buckets{$b_key}."\n";

				delete ($patternListRaw{$key});  # deletes the compressed entry
				$intol=1;
				last;
			}
		}	
		if ($intol == 0) {
			$buckets{$key}=$patternListRaw{$key};
		}
	}

	return ($cnt,$rawData, %patternListRaw);
	#print "rdata: ".$msg_parts{rawData}."\n";

	#print Dumper (%buckets);
	#print Dumper (%msg_parts);

	#modify msg_parts pattern hash
	#$patternListRaw = \%buckets;
}



################################################
# the new Log with integrated loglevel checking
sub SIGNALduino_Log3($$$)
{
  my ($name, $loglevel, $text) = @_;
 
  #DoTrigger($name,"$name $loglevel: $text") if (AttrVal($name,"eventlogging",0));
  Log3($name,$loglevel,$text);
  
  return;
}

#print Dumper (%msg_parts);
#print "\n";
#SIGNALduino_filterSign(%msg_parts);
#print Dumper (%msg_parts);
#print "\n";

1;

=pod
=item summary    supports the same low-cost receiver for digital signals
=item summary_DE Unterst&uumltzt den gleichnamigen Low-Cost Empf&aumlnger fuer digitale Signale
=begin html

<a name="SIGNALduino"></a>
<h3>SIGNALduino</h3>

	<table>
	<tr><td>
	The SIGNALduino ia based on an idea from mdorenka published at <a
	href="http://forum.fhem.de/index.php/topic,17196.0.html">FHEM Forum</a>.

	With the opensource firmware (see this <a
	href="https://github.com/RFD-FHEM/SIGNALduino">link</a>) it is capable
	to receive and send different protocols over different medias. Currently are 433Mhz protocols implemented.
	<br><br>

	The following device support is currently available:
	<br><br>


	Wireless switches  <br>
	<ul>
		<li>ITv1 & ITv3/Elro and other brands using pt2263 or arctech protocol--> uses IT.pm<br>
				In the ITv1 protocol is used to sent a default ITclock from 250 and it may be necessary in the IT-Modul to define the attribute ITclock</li>
    <li>ELV FS10 -> 10_FS10</li>
    <li>ELV FS20 -> 10_FS20</li>
	</ul>
	<br>
	
	Temperatur / humidity sensors
	<ul>
		<li>PEARL NC7159, LogiLink WS0002,GT-WT-02,AURIOL,TCM97001, TCM27 and many more -> 14_CUL_TCM97001 </li>
		<li>Oregon Scientific v2 and v3 Sensors  -> 41_OREGON.pm</li>
		<li>Temperatur / humidity sensors suppored -> 14_SD_WS07</li>
    <li>technoline WS 6750 and TX70DTH -> 14_SD_WS07</li>
    <li>Eurochon EAS 800z -> 14_SD_WS07</li>
    <li>CTW600, WH1080	-> 14_SD_WS09 </li>
    <li>Hama TS33C, Bresser Thermo/Hygro Sensor -> 14_Hideki</li>
    <li>FreeTec Aussenmodul NC-7344 -> 14_SD_WS07</li>
    <li>La Crosse WS-7035, WS-7053, WS-7054 -> 14_CUL_TX</li>
    <li>ELV WS-2000, La Crosse WS-7000 -> 14_CUL_WS</li>
	</ul>
	<br>

	It is possible to attach more than one device in order to get better
	reception, fhem will filter out duplicate messages. See more at the <a href="#global">global</a> section with attribute dupTimeout<>br><br>

	Note: this module require the Device::SerialPort or Win32::SerialPort
	module. It can currently only attatched via USB.

	</td>
	</tr>
	</table>
	<br>
	<a name="SIGNALduinodefine"></a>
	<b>Define</b>
	<ul><code>define &lt;name&gt; SIGNALduino &lt;device&gt; </code></ul>
	USB-connected devices (SIGNALduino):<br>
	<ul><li>
		&lt;device&gt; specifies the serial port to communicate with the SIGNALduino.
		The name of the serial-device depends on your distribution, under
		linux the cdc_acm kernel module is responsible, and usually a
		/dev/ttyACM0 or /dev/ttyUSB0 device will be created. If your distribution does not have a
		cdc_acm module, you can force usbserial to handle the SIGNALduino by the
		following command:
		<ul>
		modprobe usbserial 
		vendor=0x03eb
		product=0x204b
		</ul>In this case the device is most probably
		/dev/ttyUSB0.<br><br>

		You can also specify a baudrate if the device name contains the @
		character, e.g.: /dev/ttyACM0@57600<br><br>This is also the default baudrate

		It is recommended to specify the device via a name which does not change:
		e.g. via by-id devicename: /dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0@57600

		If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
		perl module Device::SerialPort is not needed, and fhem opens the device
		with simple file io. This might work if the operating system uses sane
		defaults for the serial parameters, e.g. some Linux distributions and
		OSX.  <br><br>
		</li>

	</ul>

	
	<a name="SIGNALduinoset"></a>
	<b>SET</b>
	<ul>
		<a name="close"></a>
		<li>close<br>
		Closes the connection to the device.
		</li><br>
		<a name="disableMessagetype"></a>
		<li>disableMessagetype<br>
			Allows you to disable the message processing for 
			<ul>
				<li>messages with sync (syncedMS),</li>
				<li>messages without a sync pulse (unsyncedMU)</li> 
				<li>manchester encoded messages (manchesterMC) </li>
			</ul>
			The new state will be saved into the eeprom of your arduino.
		</li><br>
		<a name="enableMessagetype"></a>
		<li>enableMessagetype<br>
			Allows you to enable the message processing for 
			<ul>
				<li>messages with sync (syncedMS)</li>
				<li>messages without a sync pulse (unsyncedMU) </li>
				<li>manchester encoded messages (manchesterMC) </li>
			</ul>
			The new state will be saved into the eeprom of your arduino.
		</li><br>
		
		<li>freq / bWidth / patable / rAmpl / sens<br>
		Only with CC1101 receiver.<br>
		Set the sduino frequency / bandwidth / PA table / receiver-amplitude / sensitivity<br>
		
		Use it with care, it may destroy your hardware and it even may be
		illegal to do so. Note: The parameters used for RFR transmission are
		not affected.<br>
		<ul>
		<a name="cc1101_freq"></a>
		<li>freq sets both the reception and transmission frequency. Note:
		    Although the CC1101 can be set to frequencies between 315 and 915
		    MHz, the antenna interface and the antenna of the CUL is tuned for
		    exactly one frequency. Default is 868.3 MHz (or 433 MHz)</li>
		<a name="cc1101_bWidth"></a>
		<li>bWidth can be set to values between 58 kHz and 812 kHz. Large values
		    are susceptible to interference, but make possible to receive
		    inaccurately calibrated transmitters. It affects tranmission too.
		    Default is 325 kHz.</li>
		<a name="cc1101_patable"></a>
		<li>patable change the PA table (power amplification for RF sending) 
		</li>
		<a name="cc1101_rAmpl"></a>
		<li>rAmpl is receiver amplification, with values between 24 and 42 dB.
		    Bigger values allow reception of weak signals. Default is 42.
		</li>
		<a name="cc1101_sens"></a>
		<li>sens is the decision boundary between the on and off values, and it
		    is 4, 8, 12 or 16 dB.  Smaller values allow reception of less clear
		    signals. Default is 4 dB.</li>
		</ul>
		</li><br>
		<a name="flash"></a>
		<li>flash [hexFile|url]<br>
			The SIGNALduino needs the right firmware to be able to receive and deliver the sensor data to fhem. In addition to the way using the
			arduino IDE to flash the firmware into the SIGNALduino this provides a way to flash it directly from FHEM.
			You can specify a file on your fhem server or specify a url from which the firmware is downloaded

			There are some requirements:
			<ul>
				<li>avrdude must be installed on the host<br>
					On a Raspberry PI this can be done with: sudo apt-get install avrdude</li>
				<li>the hardware attribute must be set if using any other hardware as an Arduino nano<br>
					This attribute defines the command, that gets sent to avrdude to flash the uC.<br></li>
			</ul>
		Example:
		<ul>
			<li>flash via hexFile: <code>set sduino flash ./FHEM/firmware/SIGNALduino_mega2560.hex</code></li>
			<li>flash via url for Nano with CC1101: <code>set sduino flash https://github.com/RFD-FHEM/SIGNALDuino/releases/download/3.3.1-RC7/SIGNALDuino_nanocc1101.hex</code></li>
		</ul><br>
		</li>
		</li>
		<u><i>note model radino:</u></i><ul>
		<li>Sometimes there can be problems flashing radino on Linux. <a href="https://wiki.in-circuit.de/index.php5?title=radino_common_problems">Here in the wiki under point "radino & Linux" is a patch!</a></li>
		<li>To activate the bootloader of the radino there are 2 variants.
		<ul><li>1) modules that contain a BSL-button:</li>
			<ul>
			- apply supply voltage<br>
			- press & hold BSL- and RESET-Button<br>
			- release RESET-button, release BSL-button<br>
			 (repeat these steps if your radino doesn't enter bootloader mode right away.)
			</ul>
			<li>2) force bootloader:<ul>
			- pressing reset button twice</ul>
			</li></ul>
		<li>In bootloader mode, the radino gets a different USB ID.</li><br>
		<b>If the bootloader is enabled, it signals with a flashing LED. Then you have 8 seconds to flash.</b>
		</li>
		</ul><br>
		<a name="reset"></a>
		<li>reset<br>
		This will do a reset of the usb port and normaly causes to reset the uC connected.
		</li><br>
		<a name="raw"></a>
		<li>raw<br>
		Issue a SIGNALduino firmware command, without waiting data returned by
		the SIGNALduino. See the SIGNALduino firmware code  for details on SIGNALduino
		commands. With this line, you can send almost any signal via a transmitter connected

        To send some raw data look at these examples:
		P<protocol id>#binarydata#R<num of repeats>#C<optional clock>   (#C is optional)<br>
		<br>Example 1: set sduino raw SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=0302030  sends the data in raw mode 3 times repeated
        <br>Example 2: set sduino raw SM;R=3;P0=500;C=250;D=A4F7FDDE  sends the data manchester encoded with a clock of 250uS
        <br>Example 3: set sduino raw SC;R=3;SR;P0=5000;SM;P0=500;C=250;D=A4F7FDDE  sends a combined message of raw and manchester encoded repeated 3 times
		</p>
		</li>
        <a name="sendMsg"></a>
		<li>sendMsg<br>
		This command will create the needed instructions for sending raw data via the signalduino. Insteaf of specifying the signaldata by your own you specify 
		a protocol and the bits you want to send. The command will generate the needed command, that the signalduino will send this.
		It is also supported to specify the data in hex. prepend 0x in front of the data part.
		<br><br>
		Please note, that this command will work only for MU or MS protocols. You can't transmit manchester data this way.
		<br><br>
		Input args are:
		<p>
		<ul><li>P<protocol id>#binarydata#R<num of repeats>#C<optional clock>   (#C is optional) 
		<br>Example binarydata: <code>set sduino sendMsg P0#0101#R3#C500</code>
		<br>Will generate the raw send command for the message 0101 with protocol 0 and instruct the arduino to send this three times and the clock is 500.
		<br>SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=03020302;</li></ul><br>
		<ul><li>P<protocol id>#0xhexdata#R<num of repeats>#C<optional clock>    (#C is optional) 
		<br>Example 0xhexdata: <code>set sduino sendMsg P29#0xF7E#R4</code>
		<br>Generates the raw send command with the hex message F7E with protocl id 29 . The message will be send four times.
		<br>SR;R=4;P0=-8360;P1=220;P2=-440;P3=-220;P4=440;D=01212121213421212121212134;
		</p></li></ul>
		</li>
	</ul>
	
	
	<a name="SIGNALduinoget"></a>
	<b>Get</b>
	<ul>
        <a name="ccconf"></a>
        <li>ccconf<br>
		Only with cc1101 receiver.
		Read some CUL radio-chip (cc1101) registers (frequency, bandwidth, etc.),
		and display them in human readable form.
		</li><br>
        <a name="ccpatable"></a>
		<li>ccpatable<br>
		read cc1101 PA table (power amplification for RF sending)
		</li><br>
        <a name="ccreg"></a>
		<li>ccreg<br>
		read cc1101 registers (99 reads all cc1101 registers)
		</li><br>
        <a name="cmds"></a>
		<li>cmds<br>
		Depending on the firmware installed, SIGNALduinos have a different set of
		possible commands. Please refer to the sourcecode of the firmware of your
		SIGNALduino to interpret the response of this command. See also the raw-
		command.
		</li><br>
        <a name="config"></a>
		<li>config<br>
		Displays the configuration of the SIGNALduino protocol category. | example: <code>MS=1;MU=1;MC=1;Mred=0</code>
		</li><br>
        <a name="freeram"></a>
		<li>freeram<br>
		Displays the free RAM.
		</li><br>
        <a name="ping"></a>
		<li>ping<br>
		Check the communication with the SIGNALduino.
		</li><br>
        <a name="protocolIDs"></a>
		<li>protocolIDs<br>
		display a list of the protocol IDs
		</li><br>
        <a name="raw"></a>
		<li>raw<br>
		Issue a SIGNALduino firmware command, and wait for one line of data returned by
		the SIGNALduino. See the SIGNALduino firmware code  for details on SIGNALduino
		commands. With this line, you can send almost any signal via a transmitter connected
		</li><br>
        <a name="uptime"></a>
		<li>uptime<br>
		Displays information how long the SIGNALduino is running. A FHEM reboot resets the timer.
		</li><br>
        <a name="version"></a>
		<li>version<br>
		return the SIGNALduino firmware version
		</li><br>		
	</ul>

	
	<a name="SIGNALduinoattr"></a>
	<b>Attributes</b>
	<ul>
	<li><a href="#addvaltrigger">addvaltrigger</a><br>
        Create triggers for additional device values. Right now these are RSSI, RAWMSG and DMSG.
        </li><br>
        <a name="blacklist_IDs"></a>
        <li>blacklist_IDs<br>
        The blacklist works only if a whitelist not exist.
        </li><br>
        <a name="cc1101_frequency"></a>
		<li>cc1101_frequency<br>
        Since the PA table values ​​are frequency-dependent, is at 868 MHz a value greater 800 required.
        </li><br>
	<a name="debug"></a>
	<li>debug<br>
	This will bring the module in a very verbose debug output. Usefull to find new signals and verify if the demodulation works correctly.
	</li><br>
	<a name="development"></a>
	<li>development<br>
	With development you can enable protocol decoding for protocolls witch are still in development and may not be very accurate implemented. 
	This can result in crashes or throw high amount of log entrys in your logfile, so be careful to use this. <br><br>
	
	Protocols flagged with a developID flag are not loaded unless specified to do so.<br>
	
	<ul><li>If the protocoll is developed well, but the logical module is not ready, developId => 'm' is set. 
    You can enable it with the attribute: <br> Specify "m" followed with the protocol id to enable it.</li>
	<li>If the flag developId => 'p' is set in the protocol defintion then the protocol ID is reserved.</li>
	<li>If the flag developId => 'y' is set in the protocol defintion then the protocol is still in development. You can enable it with the attribute:<br>
	Specify "y" followed with the protocol id to enable it.</li>
	</ul><br>
	</li>
	<li><a href="#do_not_notify">do_not_notify</a></li><br>
	<li><a href="#attrdummy">dummy</a></li><br>
    <a name="doubleMsgCheck_IDs"></a>
	<li>doubleMsgCheck_IDs<br>
	This attribute allows it, to specify protocols which must be received two equal messages to call dispatch to the modules.<br>
	You can specify multiple IDs wih a colon : 0,3,7,12<br>
	</li><br>
	<a name="flashCommand"></a>
	<li>flashCommand<br>
    	This is the command, that is executed to performa the firmware flash. Do not edit, if you don't know what you are doing.<br>
		If the attribute not defined, it uses the default settings. <b>If the user defines the attribute manually, the system uses the specifications!</b><br>
    	<ul>
		<li>default for nano, nanoCC1101, miniculCC1101, promini: <code>avrdude -c arduino -b [BAUDRATE] -P [PORT] -p atmega328p -vv -U flash:w:[HEXFILE] 2>[LOGFILE]</code></li>
		<li>default for radinoCC1101: <code>avrdude -c avr109 -b [BAUDRATE] -P [PORT] -p atmega32u4 -vv -D -U flash:w:[HEXFILE] 2>[LOGFILE]</code></li>
		</ul>
		It contains some place-holders that automatically get filled with the according values:<br>
		<ul>
			<li>[BAUDRATE]<br>
			is the speed (e.g. 57600)</li>
			<li>[PORT]<br>
			is the port the Signalduino is connectd to (e.g. /dev/ttyUSB0) and will be used from the defenition</li>
			<li>[HEXFILE]<br>
			is the .hex file that shall get flashed. There are three options (applied in this order):<br>
			- passed in set flash as first argument<br>
			- taken from the hexFile attribute<br>
			- the default value defined in the module<br>
			</li>
			<li>[LOGFILE]<br>
			The logfile that collects information about the flash process. It gets displayed in FHEM after finishing the flash process</li>
		</ul><br>
		<u><i>note:</u></i> ! Sometimes there can be problems flashing radino on Linux. <a href="https://wiki.in-circuit.de/index.php5?title=radino_common_problems">Here in the wiki under the point "radino & Linux" is a patch!</a>
    </li><br>
    <a name="hardware"></a>
	<li>hardware<br>
    When using the flash command, you should specify what hardware you have connected to the usbport. Doing not, can cause failures of the device.
		<ul>
			<li>ESP_1M: ESP8266 with 1 MB flash and CC1101 receiver</li>
			<li>ESP32: ESP32 </li>
			<li>nano: Arduino Nano 328 with cheap receiver</li>
			<li>nanoCC1101: Arduino Nano 328 wirh CC110x receiver</li>
			<li>miniculCC1101: Arduino pro Mini with CC110x receiver and cables as a minicul</li>
			<li>promini: Arduino Pro Mini 328 with cheap receiver </li>
			<li>radinoCC1101: Arduino compatible radino with cc1101 receiver</li>
		</ul>
	</li><br>
	<li>maxMuMsgRepeat <br>
	MU signals can contain multiple repeats of the same message. The results are all send to a logical module. You can limit the number of scanned repetitions. Defaukt is 4, so after found 4 repeats, the demoduation is aborted. 	
	<br></li>
    <a name="minsecs"></a>
	<li>minsecs<br>
    This is a very special attribute. It is provided to other modules. minsecs should act like a threshold. All logic must be done in the logical module. 
    If specified, then supported modules will discard new messages if minsecs isn't past.
    </li><br>
    <a name="noMsgVerbose"></a>
    <li>noMsgVerbose<br>
    With this attribute you can control the logging of debug messages from the io device.
    If set to 3, this messages are logged if global verbose is set to 3 or higher.
    </li><br>
    <a name="longids"></a>
	<li>longids<br>
        Comma separated list of device-types for SIGNALduino that should be handled using long IDs. This additional ID allows it to differentiate some weather sensors, if they are sending on the same channel. Therfor a random generated id is added. If you choose to use longids, then you'll have to define a different device after battery change.<br>
		Default is to not to use long IDs for all devices.
      <br><br>
      Examples:<PRE>
# Do not use any long IDs for any devices:
attr sduino longids 0
# Use any long IDs for all devices (this is default):
attr sduino longids 1
# Use longids for BTHR918N devices.
# Will generate devices names like BTHR918N_f3.
attr sduino longids BTHR918N
</PRE></li>
<a name="rawmsgEvent"></a>
<li>rawmsgEvent<br>
When set to "1" received raw messages triggers events
</li><br>
<a name="suppressDeviceRawmsg"></a>
<li>suppressDeviceRawmsg<br>
When set to 1, the internal "RAWMSG" will not be updated with the received messages
</li><br>
<a name="whitelist_IDs"></a>
<li>whitelist_IDs<br>
This attribute allows it, to specify whichs protocos are considured from this module.
Protocols which are not considured, will not generate logmessages or events. They are then completly ignored. 
This makes it possible to lower ressource usage and give some better clearnes in the logs.
You can specify multiple whitelistIDs wih a colon : 0,3,7,12<br>
With a # at the beginnging whitelistIDs can be deactivated.
</li><br>
   <a name="WS09_CRCAUS"></a>
   <li>WS09_CRCAUS<br>
       <br>0: CRC-Check WH1080 CRC = 0  on, default   
       <br>2: CRC = 49 (x031) WH1080, set OK
    </li>
   </ul>
							  
		   
=end html
=begin html_DE

<a name="SIGNALduino"></a>
<h3>SIGNALduino</h3>

	<table>
	<tr><td>
	Der <a href="https://wiki.fhem.de/wiki/SIGNALduino">SIGNALduino</a> ist basierend auf einer Idee von "mdorenka" und ver&ouml;ffentlicht im <a href="http://forum.fhem.de/index.php/topic,17196.0.html">FHEM Forum</a>.<br>

	Mit der OpenSource-Firmware (<a href="https://github.com/RFD-FHEM/SIGNALduino">GitHub</a>) ist dieser f&auml;hig zum Empfangen und Senden verschiedener Protokolle auf 433 und 868 Mhz.
	<br><br>
	
	Folgende Ger&auml;te werden zur Zeit unterst&uuml;tzt:
	<br><br>
	
	Funk-Schalter<br>
	<ul>
		<li>ITv1 & ITv3/Elro und andere Marken mit dem pt2263-Chip oder welche das arctech Protokoll nutzen --> IT.pm<br>
				Das ITv1 Protokoll benutzt einen Standard ITclock von 250 und es kann vorkommen, das in dem IT-Modul das Attribut "ITclock" zu setzen ist.</li>
    <li>ELV FS10 -> 10_FS10</li>
    <li>ELV FS20 -> 10_FS20</li>
	</ul>
	
	Temperatur-, Luftfeuchtigkeits-, Luftdruck-, Helligkeits-, Regen- und Windsensoren:
	<ul>
		<li>PEARL NC7159, LogiLink WS0002,GT-WT-02,AURIOL,TCM97001, TCM27 und viele anderen -> 14_CUL_TCM97001.pm</li>
		<li>Oregon Scientific v2 und v3 Sensoren  -> 41_OREGON.pm</li>
		<li>Temperatur / Feuchtigkeits Sensoren unterst&uuml;tzt -> 14_SD_WS07.pm</li>
    <li>technoline WS 6750 und TX70DTH -> 14_SD_WS07.pm</li>
    <li>Eurochon EAS 800z -> 14_SD_WS07.pm</li>
    <li>CTW600, WH1080	-> 14_SD_WS09.pm</li>
    <li>Hama TS33C, Bresser Thermo/Hygro Sensoren -> 14_Hideki.pm</li>
    <li>FreeTec Aussenmodul NC-7344 -> 14_SD_WS07.pm</li>
    <li>La Crosse WS-7035, WS-7053, WS-7054 -> 14_CUL_TX</li>
    <li>ELV WS-2000, La Crosse WS-7000 -> 14_CUL_WS</li>
	</ul>
	<br>

	Es ist m&ouml;glich, mehr als ein Ger&auml;t anzuschliessen, um beispielsweise besseren Empfang zu erhalten. FHEM wird doppelte Nachrichten herausfiltern.
	Mehr dazu im dem <a href="#global">global</a> Abschnitt unter dem Attribut dupTimeout<br><br>

	Hinweis: Dieses Modul erfordert das Device::SerialPort oder Win32::SerialPort
	Modul. Es kann derzeit nur &uuml;ber USB angeschlossen werden.
	</td>
	</tr>
	</table>
	<br>
	<a name="SIGNALduinodefine"></a>
	<b>Define</b>
	<ul><code>define &lt;name&gt; SIGNALduino &lt;device&gt; </code></ul>
	USB-connected devices (SIGNALduino):<br>
	<ul><li>
		&lt;device&gt; spezifiziert den seriellen Port f&uuml;r die Kommunikation mit dem SIGNALduino.
		Der Name des seriellen Ger&auml;ts h&auml;ngt von Ihrer  Distribution ab. In
		Linux ist das <code>cdc_acm</code> Kernel_Modul daf&uuml;r verantwortlich und es wird ein <code>/dev/ttyACM0</code> oder <code>/dev/ttyUSB0</code> Ger&auml;t angelegt. Wenn deine Distribution kein <code>cdc_acm</code> Module besitzt, kannst du usbserial nutzen um den SIGNALduino zu betreiben mit folgenden Kommandos:
		<ul>
		<li>modprobe usbserial</li>
		<li>vendor=0x03eb</li>
		<li>product=0x204b</li>
		</ul>In diesem Fall ist das Ger&auml;t h&ouml;chstwahrscheinlich
		<code>/dev/ttyUSB0</code>.<br><br>

		Sie k&ouml;nnen auch eine Baudrate angeben, wenn der Ger&auml;tename das @ enth&auml;lt, Beispiel: <code>/dev/ttyACM0@57600</code><br>Dies ist auch die Standard-Baudrate.<br><br>

		Es wird empfohlen, das Ger&auml;t &uuml;ber einen Namen anzugeben, der sich nicht &auml;ndert. Beispiel via by-id devicename: <code>/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0@57600</code><br>

		Wenn die Baudrate "directio" (Bsp: <code>/dev/ttyACM0@directio</code>), dann benutzt das Perl Modul nicht Device::SerialPort und FHEM &ouml;ffnet das Ger&auml;t mit einem file io. Dies kann funktionieren, wenn das Betriebssystem die Standardwerte f&uuml;r die seriellen Parameter verwendet. Bsp: einige Linux Distributionen und
		OSX.  <br><br>
		</li>
	</ul>
	
							  
	<a name="SIGNALduinoset"></a>
	<b>SET</b>
	<ul>
	<li>cc1101_freq / cc1101_bWidth / cc1101_patable / cc1101_rAmpl / cc1101_sens<br></li>
	(NUR bei Verwendung eines cc110x Empf&auml;nger)<br><br>
	Stellt die SIGNALduino-Frequenz / Bandbreite / PA-Tabelle / Empf&auml;nger-Amplitude / Empfindlichkeit ein.<br>
	Verwenden Sie es mit Vorsicht. Es kann Ihre Hardware zerst&ouml;ren und es kann sogar illegal sein, dies zu tun.<br>
	Hinweis: Die f&uuml;r die RFR-&Uuml;bertragung verwendeten Parameter sind nicht betroffen.<br>
			<ul>
				<a name="cc1101_freq"></a>
				<li><code>freq</code> , legt sowohl die Empfangsfrequenz als auch die &Uuml;bertragungsfrequenz fest.<br>
				Hinweis: Obwohl der CC1101 auf Frequenzen zwischen 315 und 915 MHz eingestellt werden kann, ist die Antennenschnittstelle und die Antenne des CUL auf genau eine Frequenz abgestimmt. Standard ist 868,3 MHz (oder 433 MHz)</li>
				<a name="cc1101_bWidth"></a>
				<li><code>bWidth</code> , kann auf Werte zwischen 58 kHz und 812 kHz eingestellt werden. Grosse Werte sind st&ouml;ranf&auml;llig, erm&ouml;glichen jedoch den Empfang von ungenau kalibrierten Sendern. Es wirkt sich auch auf die &Uuml;bertragung aus. Standard ist 325 kHz.</li>
				<a name="cc1101_patable"></a>
				<li><code>patable</code> , &Auml;nderung der PA-Tabelle (Leistungsverst&auml;rkung f&uuml;r HF-Senden)</li>
				<a name="cc1101_rAmpl"></a>
				<li><code>rAmpl</code> , ist die Empf&auml;ngerverst&auml;rkung mit Werten zwischen 24 und 42 dB. Gr&ouml;ssere Werte erlauben den Empfang schwacher Signale. Der Standardwert ist 42.</li>
				<a name="cc1101_sens"></a>
				<li><code>sens</code> , ist die Entscheidungsgrenze zwischen den Ein- und Aus-Werten und betr&auml;gt 4, 8, 12 oder 16 dB. Kleinere Werte erlauben den Empfang von weniger klaren Signalen. Standard ist 4 dB.</li>
			</ul><br>
	<a name="close"></a>
	<li>close<br></li>
	Beendet die Verbindung zum Ger&auml;t.<br><br>
	<a name="enableMessagetype"></a>
	<li>enableMessagetype<br>
			Erm&ouml;glicht die Aktivierung der Nachrichtenverarbeitung f&uuml;r
			<ul>
				<li>Nachrichten mit sync (syncedMS),</li>
				<li>Nachrichten ohne einen sync pulse (unsyncedMU) </li>
				<li>Manchester codierte Nachrichten (manchesterMC) </li>
			</ul>
			Der neue Status wird in den eeprom vom Arduino geschrieben.
		</li><br>
	<a name="disableMessagetype"></a>
	<li>disableMessagetype<br>
			Erm&ouml;glicht das Deaktivieren der Nachrichtenverarbeitung f&uuml;r
			<ul>
				<li>Nachrichten mit sync (syncedMS)</li>
				<li>Nachrichten ohne einen sync pulse (unsyncedMU)</li> 
				<li>Manchester codierte Nachrichten (manchesterMC) </li>
			</ul>
			Der neue Status wird in den eeprom vom Arduino geschrieben.
		</li><br>
	<a name="flash"></a>
	<li>flash [hexFile|url]<br>
	Der SIGNALduino ben&ouml;tigt die richtige Firmware, um die Sensordaten zu empfangen und zu liefern. Unter Verwendung der Arduino IDE zum Flashen der Firmware in den SIGNALduino bietet dies eine M&ouml;glichkeit, ihn direkt von FHEM aus zu flashen. Sie k&ouml;nnen eine Datei auf Ihrem fhem-Server angeben oder eine URL angeben, von der die Firmware heruntergeladen wird.
	Es gibt einige Anforderungen:
			<ul>
				<li><code>avrdude</code> muss auf dem Host installiert sein. Auf einem Raspberry PI kann dies getan werden mit: <code>sudo apt-get install avrdude</code></li>
				<li>Das Hardware-Attribut muss festgelegt werden, wenn eine andere Hardware als Arduino Nano verwendet wird. Dieses Attribut definiert den Befehl, der an avrdude gesendet wird, um den uC zu flashen.</li>
			</ul>
	Beispiele:
	<ul>
	<li>flash via hexFile: <code>set sduino flash ./FHEM/firmware/SIGNALduino_mega2560.hex</code></li>
	<li>flash via url f&uuml;r einen Nano mit CC1101: <code>set sduino flash https://github.com/RFD-FHEM/SIGNALDuino/releases/download/3.3.1-RC7/SIGNALDuino_nanocc1101.hex</code></li>
	</ul>
	</li>
	<i><u>Hinweise Modell radino:</u></i><ul>
		<li>Teilweise kann es beim flashen vom radino unter Linux Probleme geben. <a href="https://wiki.in-circuit.de/index.php5?title=radino_common_problems">Hier im Wiki unter dem Punkt "radino & Linux" gibt es einen Patch!</a></li>
		<li>Um den Bootloader vom radino zu aktivieren gibt es 2 Varianten.
		<ul><li>1) Module welche einen BSL-Button besitzen:</li>
			<ul>
			- Spannung anlegen<br>
			- dr&uuml;cke & halte BSL- und RESET-Button<br>
			- RESET-Button loslassen und danach den BSL-Button loslassen<br>
			 (Wiederholen Sie diese Schritte, wenn Ihr radino nicht sofort in den Bootloader-Modus wechselt.)
			</ul>
			<li>2) Bootloader erzwingen:<ul>
			- durch zweimaliges dr&uuml;cken der Reset-Taste</ul>
			</li>
		</ul>
		<li>Im Bootloader-Modus erh&auml;lt der radino eine andere USB ID.</li><br>
		<b>Wenn der Bootloader aktiviert ist, signalisiert er das mit dem Blinken einer LED. Dann hat man ca. 8 Sekunden Zeit zum flashen.</b>
		</li>
	</ul><br>
	<a name="raw"></a>
	<li>raw<br></li>
	Geben Sie einen SIGNALduino-Firmware-Befehl aus, ohne auf die vom SIGNALduino zur&uuml;ckgegebenen Daten zu warten. Ausf&uuml;hrliche Informationen zu SIGNALduino-Befehlen finden Sie im SIGNALduino-Firmware-Code. Mit dieser Linie k&ouml;nnen Sie fast jedes Signal &uuml;ber einen angeschlossenen Sender senden.<br>
	Um einige Rohdaten zu senden, schauen Sie sich diese Beispiele an: P#binarydata#R#C (#C is optional)
			<ul>
				<li>Beispiel 1: <code>set sduino raw SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=0302030</code> , sendet die Daten im Raw-Modus dreimal wiederholt</li>
				<li>Beispiel 2: <code>set sduino raw SM;R=3;P0=500;C=250;D=A4F7FDDE</code> , sendet die Daten Manchester codiert mit einem clock von 250&micro;S</li>
				<li>Beispiel 3: <code>set sduino raw SC;R=3;SR;P0=5000;SM;P0=500;C=250;D=A4F7FDDE</code> , sendet eine kombinierte Nachricht von Raw und Manchester codiert 3 mal wiederholt</li>
			</ul><br>
		<ul>
         <u>NUR f&uuml;r DEBUG Nutzung | <small>Befehle sind abh&auml;nging vom Firmwarestand!</small></u><br>
         <small>(Hinweis: Die falsche Benutzung kann zu Fehlfunktionen des SIGNALduino´s f&uuml;hren!)</small>
            <li>CED -> Debugausgaben ein</li>
            <li>CDD -> Debugausgaben aus</li>
            <li>CDL -> LED aus</li>
            <li>CEL -> LED ein</li>
            <li>CER -> Einschalten der Datenkomprimierung (config: Mred=1)</li>
            <li>CDR -> Abschalten der Datenkomprimierung (config: Mred=0)</li>
            <li>CSmscnt=[Wert] -> Wiederholungsz&auml;hler f&uuml;r den split von MS Nachrichten</li>
            <li>CSmuthresh=[Wert] -> Schwellwert f&uuml;r den split von MU Nachrichten (0=aus)</li>
            <li>CSmcmbl=[Wert] -> minbitlen f&uuml;r MC-Nachrichten</li>
            <li>CSfifolimit=[Wert] -> Schwellwert f&uuml;r debug Ausgabe der Pulsanzahl im FIFO Puffer</li>
         </ul><br>
	<a name="reset"></a>
	<li>reset<br></li>
	&Ouml;ffnet die Verbindung zum Ger&auml;t neu und initialisiert es. <br><br>
	<a name="sendMsg"></a>
	<li>sendMsg</li>
	Dieser Befehl erstellt die erforderlichen Anweisungen zum Senden von Rohdaten &uuml;ber den SIGNALduino. Sie k&ouml;nnen die Signaldaten wie Protokoll und die Bits angeben, die Sie senden m&ouml;chten.<br>
	Alternativ ist es auch m&ouml;glich, die zu sendenden Daten in hexadezimaler Form zu &uuml;bergeben. Dazu muss ein 0x vor den Datenteil geschrieben werden.
	<br><br>
	Bitte beachte, dieses Kommando funktioniert nur f&uuml;r MU oder MS Protokolle nach dieser Vorgehensweise:
		<br><br>
		Argumente sind:
		<p>
		<ul><li>P<protocol id>#binarydata#R<anzahl der wiederholungen>#C<optional taktrate>   (#C is optional) 
		<br>Beispiel binarydata: <code>set sduino sendMsg P0#0101#R3#C500</code>
		<br>Wird eine sende Kommando f&uuml;r die Bitfolge 0101 anhand der protocol id 0 erzeugen. Als Takt wird 500 verwendet.
		<br>SR;R=3;P0=500;P1=-9000;P2=-4000;P3=-2000;D=03020302;<br></li></ul><br>
		<ul><li>P<protocol id>#0xhexdata#R<anzahl der wiederholungen>#C<optional taktrate>    (#C is optional) 
		<br>Beispiel 0xhexdata: <code>set sduino sendMsg P29#0xF7E#R4</code>
		<br>Wird eine sende Kommando f&uuml;r die Hexfolge F7E anhand der protocol id 29 erzeugen. Die Nachricht soll 4x gesenset werden.
		<br>SR;R=4;P0=-8360;P1=220;P2=-440;P3=-220;P4=440;D=01212121213421212121212134;
		</p></li></ul>
	</ul><br>
	</ul>
	
	
	<a name="SIGNALduinoget"></a>
	<b>Get</b>
	<ul>
	<a name="ccconf"></a>
	<li>ccconf<br></li>
   Liest s&auml;mtliche radio-chip (cc1101) Register (Frequenz, Bandbreite, etc.) aus und zeigt die aktuelle Konfiguration an.<br>
   (NUR bei Verwendung eines cc1101 Empf&auml;nger)<br><br>
	<a name="ccpatable"></a>
	<li>ccpatable<br></li>
   Liest die cc1101 PA Tabelle aus (power amplification for RF sending).<br><br>
	<a name="ccreg"></a>
	<li>ccreg<br></li>
   Liest das cc1101 Register aus (99 reads all cc1101 registers).<br><br>
	<a name="cmds"></a>
	<li>cmds<br></li>
	Abh&auml;ngig von der installierten Firmware besitzt der SIGNALduino verschiedene Befehle. Bitte beachten Sie den Quellcode der Firmware Ihres SIGNALduino, um die Antwort dieses Befehls zu interpretieren.<br><br>
	<a name="config"></a>
	<li>config<br></li>
	Zeigt Ihnen die aktuelle Konfiguration der SIGNALduino Protokollkathegorie an. | Bsp: <code>MS=1;MU=1;MC=1;Mred=0</code><br><br>
	<a name="freeram"></a>
	<li>freeram<br></li>
   Zeigt den freien RAM an.<br><br>
	<a name="ping"></a>
   <li>ping<br></li>
	Pr&uuml;ft die Kommunikation mit dem SIGNALduino.<br><br>
	<a name="protocolIDs"></a>
	<li>protocolIDs<br></li>
	Zeigt Ihnen die aktuell implementierten Protokolle des SIGNALduino an und an welches FHEM Modul Sie &uuml;bergeben werden.<br><br>
	<a name="raw"></a>
	<li>raw<br></li>
	Abh&auml;ngig von der installierten Firmware! Somit k&ouml;nnen Sie einen SIGNALduino-Firmware-Befehl direkt ausf&uuml;hren.<br><br>
	<a name="uptime"></a>
	<li>uptime<br></li>
	Zeigt Ihnen die Information an, wie lange der SIGNALduino l&auml;uft. Ein FHEM Neustart setzt den Timer zur&uuml;ck.<br><br>
	<a name="version"></a>
	<li>version<br></li>
	Zeigt Ihnen die Information an, welche aktuell genutzte Software Sie mit dem SIGNALduino verwenden.<br><br>
	</ul>
	
	
	<a name="SIGNALduinoattr"></a>
	<b>Attributes</b>
	<ul>
	<a name="addvaltrigger"></a>
	<li>addvaltrigger<br></li>
	Generiert Trigger f&uuml;r zus&auml;tzliche Werte. Momentan werden DMSG , RAWMSG und RSSI unterst&uuml;zt.<br><br>
	<li><a href="#dummy">dummy</a><br><br></li>
	<a name="blacklist_IDs"></a>
	<li>blacklist_IDs<br></li>
	Dies ist eine durch Komma getrennte Liste. Die Blacklist funktioniert nur, wenn keine Whitelist existiert! Hier kann man ID´s eintragen welche man nicht ausgewertet haben m&ouml;chte.<br><br>
	<a name="cc1101_frequency"></a>
	<li>cc1101_frequency<br></li>
	Frequenzeinstellung des cc1101. | Bsp: 433.920Mhz / 868.350Mhz<br><br>
	<a name="debug"></a>
	<li>debug<br>
	Dies bringt das Modul in eine sehr ausf&uuml;hrliche Debug-Ausgabe im Logfile. Somit lassen sich neue Signale finden und Signale &uuml;berpr&uuml;fen, ob die Demodulation korrekt funktioniert.</li><br>
	<a name="development"></a>
	<li>development<br>
	Mit development k&ouml;nnen Sie die Protokolldekodierung f&uuml;r Protokolle aktivieren, die sich noch in der Entwicklung befinden und m&ouml;glicherweise nicht sehr genau implementiert sind.
	Dies kann zu Abst&uuml;rzen oder zu einer hohen Anzahl an Log-Eintr&auml;gen in Ihrer Logdatei f&uuml;hren. Protokolle, die mit einem developmentID-Flag gekennzeichnet sind, werden nicht geladen, sofern dies nicht angegeben ist.<br>
	<ul><li>Wenn das Flag developId => 'm' in der Protokolldefinition gesetzt ist, befindet sich das logische Modul in der Entwicklung.
	Wenn Sie es aktivieren wollen, so geben Sie "m" gefolgt von der Protokoll-ID an.</li>
	<li>Wenn das Flag developId => 'p' in der Protokolldefinition gesetzt ist, wurde die ID reserviert.</li>
	<li>Wenn das Flag developId => 'y' in der Protokolldefinition gesetzt ist, befindet sich das Protokoll noch in der Entwicklung.
	Wenn Sie es aktivieren wollen, so geben Sie "y" gefolgt von der Protokoll-ID an.</li></a></li></ul><br>
	<li><a href="#do_not_notify">do_not_notify</a></li><br>
	<a name="doubleMsgCheck_IDs"></a>
	<li>doubleMsgCheck_IDs<br></li>
	Dieses Attribut erlaubt es, Protokolle anzugeben, die zwei gleiche Nachrichten enthalten m&uuml;ssen, um diese an die Module zu &uuml;bergeben. Sie k&ouml;nnen mehrere IDs mit einem Komma angeben: 0,3,7,12<br><br>
	<a name="flashCommand"></a>
	<li>flashCommand<br>
	Dies ist der Befehl, der ausgef&uuml;hrt wird, um den Firmware-Flash auszuf&uuml;hren. Nutzen Sie dies nicht, wenn Sie nicht wissen, was Sie tun!<br>
	Wurde das Attribut nicht definiert, so verwendet es die Standardeinstellungen. <b>Sobald der User das Attribut manuell definiert, nutzt das System die Vorgaben!</b><br>
	<ul>
	<li>Standard nano, nanoCC1101, miniculCC1101, promini: <code>avrdude -c arduino -b [BAUDRATE] -P [PORT] -p atmega328p -vv -U flash:w:[HEXFILE] 2>[LOGFILE]</code></li>
	<li>Standard radinoCC1101: <code>avrdude -c avr109 -b [BAUDRATE] -P [PORT] -p atmega32u4 -vv -D -U flash:w:[HEXFILE] 2>[LOGFILE]</code></li>
	</ul>
	Es enth&auml;lt einige Platzhalter, die automatisch mit den entsprechenden Werten gef&uuml;llt werden:
		<ul>
			<li>[BAUDRATE]<br>
			Ist die Schrittgeschwindigkeit. (z.Bsp: 57600)</li>
			<li>[PORT]<br>
			Ist der Port, an den der SIGNALduino angeschlossen ist (z.Bsp: /dev/ttyUSB0) und wird von der Defenition verwendet.</li>
			<li>[HEXFILE]<br>
			Ist die .hex-Datei, die geflasht werden soll. Es gibt drei Optionen (angewendet in dieser Reihenfolge):<br>
			&nbsp;&nbsp;- in <code>set SIGNALduino flash</code> als erstes Argument &uuml;bergeben<br>
			&nbsp;&nbsp;- aus dem Hardware-Attribut genommen<br>
			&nbsp;&nbsp;- der im Modul definierte Standardwert<br>
			</li>
			<li>[LOGFILE]<br>
			Die Logdatei, die Informationen &uuml;ber den Flash-Prozess sammelt. Es wird nach Abschluss des Flash-Prozesses in FHEM angezeigt</li>
		</ul><br>
	<u><i>Hinweis:</u></i> ! Teilweise kann es beim flashen vom radino unter Linux Probleme geben. <a href="https://wiki.in-circuit.de/index.php5?title=radino_common_problems">Hier im Wiki unter dem Punkt "radino & Linux" gibt es einen Patch!</a>
	</li><br>
	<a name="hardware"></a>
	<li>hardware<br>
		Derzeit m&ouml;gliche Hardware Varianten:
		<ul>
			<li>ESP_1M: ESP8266 mit 1 MB Flash und einem CC1101</li>
			<li>ESP32: ESP32 </li>
			<li>nano: Arduino Nano 328 f&uuml;r "Billig"-Empf&auml;nger</li>
			<li>nanoCC1101: Arduino Nano f&uuml;r einen CC110x-Empf&auml;nger</li>
			<li>miniculCC1101: Arduino pro Mini mit einen CC110x-Empf&auml;nger entsprechend dem minicul verkabelt</li>
			<li>promini: Arduino Pro Mini 328 f&uuml;r "Billig"-Empf&auml;nger</li>
			<li>radinoCC1101: Ein Arduino Kompatibler Radino mit cc1101 receiver</li>
		</ul><br>
		Notwendig f&uuml;r den Befehl <code>flash</code>. Hier sollten Sie angeben, welche Hardware Sie mit dem usbport verbunden haben. Andernfalls kann es zu Fehlfunktionen des Ger&auml;ts kommen.<br>
	</li><br>
	<a name="longids"></a>
	<li>longids<br></li>
	Durch Komma getrennte Liste von Device-Typen f&uuml;r Empfang von langen IDs mit dem SIGNALduino. Diese zus&auml;tzliche ID erlaubt es Wettersensoren, welche auf dem gleichen Kanal senden zu unterscheiden. Hierzu wird eine zuf&auml;llig generierte ID hinzugef&uuml;gt. Wenn Sie longids verwenden, dann wird in den meisten F&auml;llen nach einem Batteriewechsel ein neuer Sensor angelegt. Standardm&auml;ssig werden keine langen IDs verwendet.
	Folgende Module verwenden diese Funktionalit&auml;t: 14_Hideki, 41_OREGON, 14_CUL_TCM97001, 14_SD_WS07.<br>
	Beispiele:<br>
	<br>
    # Keine langen IDs verwenden (Default Einstellung):<br>
    attr SIGNALduino longids 0<br>
    # Immer lange IDs verwenden:<br>
    attr SIGNALduino longids 1<br>
    # Verwende lange IDs f&uuml;r SD_WS07 Devices.<br>
    # Device Namen sehen z.B. so aus: SD_WS07_TH_3 for channel 3.<br>
    attr SIGNALduino longids SD_WS07<br><br>
	<a name="maxMuMsgRepeat "></a>
	<li>maxMuMsgRepeat <br><
	In MU Signalen k&ouml;nnen mehrere Wiederholungen stecken. Diese werden einzeln ausgewertet und an ein logisches Modul &uuml;bergeben. Mit diesem Attribut kann angepasst werden, wie viele Wiederholungen gesucht werden. Standard ist 4. 	
	<br></li>
	<a name="minsecs"></a>
	<li>minsecs<br></li>
	Es wird von anderen Modulen bereitgestellt. Minsecs sollte wie eine Schwelle wirken. Wenn angegeben, werden unterst&uuml;tzte Module neue Nachrichten verworfen, wenn minsecs nicht vergangen sind.<br><br>
	<a name="noMsgVerbose"></a>
	<li>noMsgVerbose<br></li>
	Mit diesem Attribut k&ouml;nnen Sie die Protokollierung von Debug-Nachrichten vom io-Ger&auml;t steuern. Wenn dieser Wert auf 3 festgelegt ist, werden diese Nachrichten protokolliert, wenn der globale Verbose auf 3 oder h&ouml;her eingestellt ist.<br><br>
	<a name="rawmsgEvent"></a>
	<li>rawmsgEvent<br></li>
	Bei der Einstellung "1", l&ouml;sen empfangene Rohnachrichten Ereignisse aus.<br><br>
	<a name="suppressDeviceRawmsg"></a>
	<li>suppressDeviceRawmsg</li>
	Bei der Einstellung "1" wird das interne "RAWMSG" nicht mit den empfangenen Nachrichten aktualisiert.<br><br>
	<a name="whitelist_IDs"></a>
	<li>whitelist_IDs<br></li>
	Dieses Attribut erlaubt es, festzulegen, welche Protokolle von diesem Modul aus verwendet werden. Protokolle, die nicht beachtet werden, erzeugen keine Logmeldungen oder Ereignisse. Sie werden dann vollst&auml;ndig ignoriert.
	Dies erm&ouml;glicht es, die Ressourcennutzung zu reduzieren und bessere Klarheit in den Protokollen zu erzielen. Sie k&ouml;nnen mehrere WhitelistIDs mit einem Komma angeben: 0,3,7,12. Mit einer # am Anfang k&ouml;nnen WhitelistIDs deaktiviert werden. <br><br>
	<a name="WS09_CRCAUS"></a>
	<li>WS09_CRCAUS<br>
		<ul>
			<li>0: CRC-Check WH1080 CRC = 0 on, Standard</li>
			<li>2: CRC = 49 (x031) WH1080, set OK</li>
		</ul>
	</li><br>
	
=end html_DE
=cut
