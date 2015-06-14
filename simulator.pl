#    Original VB script: 
#    Copyright (C) 2009 Ian Richardson, Murray Thomson
#    CREST (Centre for Renewable Energy Systems Technology),
#    Department of Electronic and Electrical Engineering
#    Loughborough University, Leicestershire LE11 3TU, UK
#    Tel. +44 1509 635326. Email address: I.W.Richardson2@lboro.ac.uk

#    Perl implementation:
#    Copyright (C) 2010 Gergely Acs <acs@crysys.hu>

#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.

#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

use Getopt::Std;

use lib './lib';
use lib '../../lib/accessors-1.01/lib';
use lib '../../lib/Switch-2.16';
use lib '../../lib';
use lib '../../lib/Date-Calc-6.3/lib/Date';
use lib '../../lib/List-MoreUtils-0.26/lib/List';

use lib './SimElec/source/SimElec/lib';            #libraries path in respect to the JAVA working directory (not required when run in perl)
use lib './SimElec/lib/accessors-1.01/lib';
use lib './SimElec/lib/Switch-2.16';
use lib './SimElec/lib';
use lib './SimElec/lib/Date-Calc-6.3/lib/Date';
use lib './SimElec/lib/List-MoreUtils-0.26/lib/List';

use strict;

use ApplianceModel;
use LightingModel;
use OccupancyModel;
use Appliance;
use ApplianceSimData1;
use OccSimData;
use Bulbs;
use LightSimData;
use LightConfig;
use OccStartStates;
use ActivityStats;
use OccStates;
use Irradiance;

my @month_names = ('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December');

my $stat_dir = "./SimElec/source/SimElec/stat/";   #for working in java
#my $stat_dir = "./stat/";                         #for working in perl

my $out_dir = "./IN/";                             #for working in java
#my $out_dir = "../../../IN/";                      #for working in perl

my @power_washing_machine = (((100) x 15), ((2000) x 15), ((900) x 15), ((100) x 15), ((100) x 15), ((300) x 15), ((50) x 15));
my @power_dish_washer = (((80) x 15), ((2000) x 15) ,((80) x 15), ((80) x 15), ((80) x 15), ((2000) x 15), ((300) x 15), ((150) x 15));
my @power_tumble_dryer = (((2000) x 15), ((2000) x 15), ((2000) x 15), ((1600) x 15), ((1300) x 15), ((940) x 15));
my @apl_consum=((0) x 1440); #stores the appliances consumption from all the houses(power ratings from Smart-A project) 


mkdir $out_dir;

sub LoadAppliancesFromFile
{
	die("Unable to open $_[0]!\n") unless open (IN, $_[0]);

	my $id = 0;
	my @appliances;

	while (<IN>)
	{
		next if $_ =~ /#.*/;
		my @item = split /[,\n]/;

		#$global_calibration = $item[1], next if $item[0] eq "Calibration";
		next if $item[0] eq "Calibration" || $item[0] eq "Mean active occupancy";
		#$global_mean_active_occ = $item[1], next if $item[0] eq "Mean active occupancy";

		my $appliance = new Appliance();

		$appliance->ID($id++);

		$appliance->Name($item[0]);  
		$appliance->Type($item[16]);  
		$appliance->MeanCycleLength($item[4]); 
		$appliance->CyclesPerYear($item[3]); 
		$appliance->StandbyPower($item[6]); 
		$appliance->RatedPower($item[5]); 
		$appliance->Calibration($item[19]);
		$appliance->Ownership($item[1]); 
		$appliance->TargetAveragekWhYear($item[22]); 
		$appliance->UserProfile($item[17]); 
		$appliance->RestartDelay($item[7]);

		#print "ID: ", $appliance->ID,"\n";
		#print "Name: ", $appliance->Name,"\n";
		#print "Type: ", $appliance->Type,"\n";
		#print "Mean cycle len: ", $appliance->MeanCycleLength,"\n";
		#print "Standby power: ", $appliance->StandbyPower,"\n";
		#print "Rated power: ", $appliance->RatedPower,"\n";
		#print "Calibration: ", $appliance->Calibration,"\n";
		#print "Ownership: ", $appliance->Ownership,"\n";
		#print "Target Avg.Wh.Year: ", $appliance->TargetAveragekWhYear,"\n";
		#print "User profile: ", $appliance->UserProfile,"\n";
		#print "Restart delay: ", $appliance->RestartDelay,"\n\n";

		push @appliances, $appliance;
	}
	
	close IN;
	return @appliances;
}

my %args;
my $x;
my $counterx =0; #modified on 24.04.2013 (only simulator2) variable enabled to enable $nrofdays > 31; will iterate $sMonth

getopts("n:r:m:z:",\%args);  #number of houses : number of residents in house : month number : number of days

#$args{n}=3;
#$args{m}=4;
#$args{d}="we";


die "Usage: simulator2.pl -n <number_of_users> [-r <residents_num>] -m <month> -d <we|wd>\n" if !defined $args{n} || !defined $args{m} || !defined $args{z};

my($nrofdays)=$args{z};
my ($users_num, $sMonth) = ($args{n}, $args{m});

	for $x (1 .. $nrofdays)                    # the iterator for the number of days
		{    
		if ( ($x%6)== 0 || ($x%7)== 0 )          # if the day iterator reaches a saturday or a sunday
			{ $args{d}="we";                            # make the day variable equal to "we"
			} else {
			$args{d}="wd";
			}
        
		if ($counterx ==31){    #modified on 24.04.2013 (only simulator2) variable enabled to enable $nrofdays > 31; will iterate $sMonth
			$sMonth++ ;
			$counterx =0;}
	    $counterx++ ;

my $bWeekend = $args{d} eq "we" ? 1 : 0;

# modification 23/01/13 my $residentsNum = !defined $args{r} ? &GetResidentNumber() : $args{r} ;

# Perform a range check on the input month
die "Please give the month of the year from 1 to 12." if ($sMonth < 1 || $sMonth > 12);

# die "Please enter the number of residents from 1 to 5." unless ($residentsNum <= 5 && $residentsNum >= 1);

my @appliances = LoadAppliancesFromFile($stat_dir . "appliances.csv");
my $activity_stats = new ActivityStats();
my $bulbs = new Bulbs();
my $irradiance = new Irradiance();
my $light_config = new LightConfig();
my $occ_start_states = new OccStartStates();

# Initialization
$activity_stats->LoadFromFile($stat_dir . "activity_stats.csv");
$bulbs->LoadFromFile($stat_dir . "bulbs.csv");
$irradiance->LoadFromFile($stat_dir . "irradiance.csv");
$light_config->LoadFromFile($stat_dir . "light_config.csv");
$occ_start_states->LoadFromFile($stat_dir . "occ_start_states.csv");

my $Appliance_Model = new ApplianceModel(); 
my $Lighting_Model = new LightingModel(); 
my $Occupancy_Model = new OccupancyModel(); 

my @all_of_consumption;  #stores the house consumption without appliances (power ratings from I. Richardson)
my @all_of_consumption_apl; #stores the house consumption with appliances (power ratings from I. Richardson)
my @tmp;  #stores the house consumption without appliances (power ratings from I. Richardson)
my @tmp_apl; #stores the house consumption with appliances (power ratings from I. Richardson)
my @all_light;  #stores the light consumption for all the houses
my @tmp_start_times; 
my @start_times;  # stores the start times ( a 1440 x 3 array) of the appl (wm,dw,td) in all the houses
my $residentsNum; # stores the number of residents for the current house

foreach my $num  (1..$users_num)    #second loop for cycling through the first to the last house
{
# Models
    $residentsNum = !defined $args{r} ? &GetResidentNumber() : $args{r} ;
#modification 23/01/13 	$residentsNum = int(rand(5) + 1) if !defined $args{r};    
	#print "Generating dwelling $num [residents: $residentsNum, month: $sMonth, $args{d}]...";

# Data and statistics
	my $light_sim_data = new LightSimData();
	my $occ_sim_data = new OccSimData();
	my $appliance_sim_data = new ApplianceSimData1();
	my $occ_states = new OccStates();

	$occ_states->LoadFromFile($stat_dir . "tpm" . $residentsNum . "_" . $args{d} . ".csv");

	$irradiance->Month($sMonth);

# Installing appliances
	$Appliance_Model->ConfigureAppliancesInDwelling(\@appliances);

	# print "\nDwelling appliances:\n\n";

	#print $_->Name(), " : ", ($_->HasAppliance ? "yes" : "no"), "\n" foreach (@appliances);

	# print "\nAppliances have been allocated.\n"; 

# Run the occupancy simulation
	$Occupancy_Model->RunOccupancySimulation($residentsNum, $bWeekend, $occ_start_states, $occ_states, $occ_sim_data);

# Run the lighting simulation
	$Lighting_Model->RunLightingSimulation($light_config, $light_sim_data, $occ_sim_data, $irradiance, $bulbs);

# Run the appliance model simulation
	$Appliance_Model->RunApplianceSimulation(\@appliances, $sMonth, $bWeekend, $Lighting_Model, $occ_sim_data, 
			$appliance_sim_data, $activity_stats);
	my @lighting_consumption = $light_sim_data->GetPowerOnTime();
	
# Adds all the light consumption for all the houses: $all_light
	for $a (0 .. $#lighting_consumption)
    {
        $all_light[$a] = $lighting_consumption[$a];
    }

# Adds light consumption to the overall consumption
	$appliance_sim_data->AddLighting(@lighting_consumption);
	
#	$all_of_consumption = $all_of_consumption + $appliance_sim_data;

# Adds all the consumption WITHOUT wm,dw and td for all the houses: 
	@tmp=$appliance_sim_data->GetSumConsumption; 
	
	for $a (0 .. $#tmp)
    {	
		$all_of_consumption[$a] = $all_of_consumption[$a] + $tmp[$a]+$all_light[$a];
	}
	#print "\n";

	
# Adds all the consumption WITH wm,dw and td for all the houses: 
	@tmp_apl=$appliance_sim_data->GetSumConsumptionWithAppl; 	
		for $a (0 .. $#tmp_apl)
    {	
		$all_of_consumption_apl[$a] = $all_of_consumption_apl[$a] + $tmp_apl[$a]+$all_light[$a];
	}
	
# The start times of the three appliances for each house are stored in tmp_start_times ( 1440 X 3) and added to the start time matrix of all houses 	
	@tmp_start_times=$Appliance_Model->GetStartTimes;
	
	for $a (0 .. $#tmp_start_times)
		{	for $b (0 .. 3)
			{ $start_times[$a][$b] = $start_times[$a][$b] + $tmp_start_times[$a][$b];
			}
		}

# Writing simulation data
#	$occ_sim_data->WriteToFile($out_dir . "$num-occ_sim_data.csv");

#	$appliance_sim_data->WriteToFile($out_dir . "$num-appliance_sim_data.csv", $out_dir . "$num-all_power.csv", \@lighting_consumption);
	
#	$light_sim_data->WriteToFile($out_dir . "$num-light_sim_data.csv");

# Generating plots
#	my $lighting_title = 'Lighting power (' . ($bWeekend ? "weekend, " : "weekday, ") .
#			$month_names[$sMonth-1] .  ", $residentsNum residents) ";
#	$light_sim_data->MakePlot($out_dir . "$num-light_sim_data.eps", $lighting_title);
#
#	my $occ_sim_title = 'Number of active occupants (' .
#		($bWeekend ? "weekend, " : "weekday, ") . $month_names[$sMonth-1] .  ", $residentsNum residents) ";
#	$occ_sim_data->MakePlot($out_dir . "$num-occ_sim_data.eps", $occ_sim_title);
#
#	my $consumption_title = 'Power (' . ($bWeekend ? "weekend, " : "weekday, ") . $month_names[$sMonth-1] .
#					", $residentsNum residents) ";
#	my $usage_title = 'Usage of appliances (' . ($bWeekend ? "weekend, " : "weekday, ") .
#		$month_names[$sMonth-1] .  ", $residentsNum residents) ";
#	$appliance_sim_data->MakePlots($out_dir. "$num-all_power.eps", $consumption_title, $out_dir . "$num-usage.eps", $usage_title);
#
#	print "\n";

}

# Saving all_consumption without appliances(wm,dw,td) in a csv file named all_power.csv;

die("Unable to open all consumption file") unless open (OUT, ">" . $out_dir . "$x all_power.csv");

	$" = ",";
	for (my $i = 0; $i < scalar(@all_of_consumption); $i++)
	{
		print OUT "$all_of_consumption[$i],\n"; 
	}

	close OUT;

# saving the consumption with apl (power ratings from I. Richrdson) in a csv file named all_power_apl.csv

	die("Unable to open all consumption file") unless open (OUT, ">" . $out_dir . "$x all_power_apl.csv");

	$" = ",";
	for (my $i = 0; $i < scalar(@all_of_consumption_apl); $i++)
	{
		print OUT "$all_of_consumption_apl[$i],\n"; 
	}

	close OUT;


# saving the start times of the appl(wm,dw,td) of ALL the houses

	die("Unable to open start times file") unless open (OUT, ">" . $out_dir . "$x start_time.csv");

	$" = ",";
	for (my $i = 0; $i < scalar(@start_times); $i++)
	{   for (my $j = 0; $j < 3; $j++) {
		print OUT "$start_times[$i][$j],"; 
	}   
	   print OUT "\n";
	}

	close OUT; 

# saving the energy consumed by the appliances (with Values from Smart-a project) based on @start times
	
	for (my $i = 0; $i < scalar(@start_times); $i++)
	{ if( $start_times[$i][0] != 0)
		{ for( my $j=0; $j<scalar(@power_washing_machine); $j++)
			{  $apl_consum[$i+$j]= $apl_consum[$i+$j] + $start_times[$i][0] * $power_washing_machine[$j]; 
			}
		}
		
		if( $start_times[$i][1] != 0)
		{ for( my $j=0; $j<scalar(@power_dish_washer); $j++)
			{  $apl_consum[$i+$j]= $apl_consum[$i+$j] + $start_times[$i][1] * $power_dish_washer[$j]; 
			}
		}
		
		if( $start_times[$i][2] != 0)
		{ for( my $j=0; $j<scalar(@power_tumble_dryer); $j++)
			{  $apl_consum[$i+$j]= $apl_consum[$i+$j] + $start_times[$i][2] * $power_tumble_dryer[$j]; 
			}
		}
		
	}
		
	die("Unable to open start times file") unless open (OUT, ">" . $out_dir . "$x apl_consum.csv");

	$" = ",";
	for (my $i = 0; $i < scalar(@apl_consum); $i++)
	{
		print OUT "$apl_consum[$i],\n"; 

	}

	close OUT; 
	
	@apl_consum=((0) x 1440);
}	

# Subrutine introduce by Silviu to simulate the Household ditribution by number of people living in them
# 1 pers - 29%  // 2 pers - 35% // 3 pers - 16.5% // 4 pers - 13 % // more than 4 - 6.5% 

sub GetResidentNumber
{
        my @resident;
	
		my $random = rand(100);
		
		my $resident=1;
		
		
		if ($random <=29) {
			$resident = 1;
							}
		if (($random >29) && ($random <=64)) {
			$resident = 2;
							}
		if (($random >64) && ($random <=80.5)) {
			$resident = 3;
							}
		if (($random >80.5) && ($random <=93.5)) {
			$resident = 4;
							}
        if ($random >93.5) {
			$resident = 5;
							} 
        						
	

	return $resident;
}			
	
