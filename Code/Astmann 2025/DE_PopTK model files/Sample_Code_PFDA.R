#### Environmental PFAS exposure model for cattle 
## Authors: Antti Mikkonen (UniSA/EPA VIC) and Barbara Astmann (MECDC)
#Version: V1.1

############################PFDA EXPOSURE MODEL########################################

########################### Load libraries #######################################
library(dplyr)
library(ggplot2)
library(tidyr)
library(plotly)
library(tidyverse)
library(scales)
library(ggpubr)
library(ggrepel)
library(egg)
library(ggExtra)
library(gridExtra)
library(cowplot)

################## Clear the workspace before starting #################################
rm(list=ls(all=TRUE))

######### Fixed Animal Parameters ###############################################################
MW <- 640 # mature weight for cattle (kg) (Freer et al. 2012)
Cgr <- 0.0115 # growth rate constant (kg^0.27d) (Freer et al. 2012; Brody 1945)
Cgrs <- 0.27 # allometric scaling factor for growth (Freer et al. 2012; Taylor StC.S 1968)
Cq <-	1.7	#	Effect of relative size on PI - quadratic parameter) (Freer et al. 2012; Sheep Explorer)
Cbc <- 1.5	#	Effect of body condition on potential intake (Freer et al. 2012; Sheep Explorer)
Crc <- 1 # Relative condition, is defined as the ratio of current base weight, W, to normal weight. Relative condition is related to condition score, as defined by Jefferies (1961) and Earle (1976), through the convention of SCA (1990) that a gain or loss of 1 unit of condition score is equivalent to a change of 0.15N for the 0-5 scale (sheep and beef cattle) or to 0.09N for the 1-8 scale (dairy cattle).
Crs <-	0.025	# kg kg-1	Effect of relative size on PI - scalar (Freer et al. 2012; Sheep Explorer)
DEf <- 2.895 #Mean of grass DE values from NRC 2000
YP <- 8.16 #Peak milk yield for cow adjusted for breed, Based on PML=8.16 and PL=5, eq. 5 in Tedeschi and Fox 2009)
L <- 48.16 
A <- 1.688
B <-0.568435966
C <- 0.009144723

################### Intake Params ########################################################### 
temporal_data <- read.csv("2022_Exposure.csv") #Insert file path of "2022_Exposure.csv" file

colnames(temporal_data)

## this is to get rid of PFOS concentrations
temporal_data <- temporal_data %>%
  dplyr::select(-8, -9, -10, -11)

################## Dataframe - Spring ######################## 
TIME <- temporal_data$Date
DAYS <- temporal_data$Days
TEMP  <- temporal_data$Temp
DMPER <- temporal_data$DMperc
DMFRAC <- temporal_data$DMfrac
RF <- temporal_data$RF

#######################################################################################
########### Estimating intakes from different matrices ##########################################

# Estimate BW over time (regression analysis Freer et al 2012)
INT <- temporal_data %>% mutate(
  BW = MW - MW*0.9*2.71828**(-(Cgr*DAYS)/MW^Cgrs)) %>% mutate(
    Z = BW/MW)

#### Estimate milk intake for calves
INT <- INT %>% mutate(
  MY=((A*((DAYS+14)^B)*(exp(-C*(DAYS+14))))*YP)/10)

#Calculate DMI from milk
INT <- INT %>% mutate(
  DMI_milk=(MY*0.13))

# Estimate Dry matter intake from forage (based on BW and NDF regression) 
#this will depend on milk intake until time of weaning. Adjust for days on milk.
INT <- INT %>% mutate(
  DMI = case_when(
    DAYS <=166 ~ ((0.0783*BW)-(4.87*DMI_milk))/DEf,
    DAYS >166 ~ Crs*MW*Z*(Cq-Z)*(Crc*(Cbc-Crc)/(Cbc-1))))

# Estimate pasture water intake (based on BW and DM content) 
INT <- INT %>% mutate(
  PWI = (DMI/DMFRAC)*(1-DMFRAC)) 

# Estimate water needs for temperature (cattle) 
INT <- INT %>% mutate(
  DWI = case_when(
    BW <= 364 & TEMP > 21.1 ~ -69.11+2.76*TEMP+0.1159*BW,
    BW > 364 & TEMP > 21.1 ~ -51.77+4.01*TEMP,
    BW <= 454 & TEMP <= 21.1 ~ -3.69+0.074*BW+0.68*TEMP,
    BW > 454 & TEMP <= 21.1 ~ 3.83+0.89*TEMP+0.0341*BW)) 

#### Free water intake (FWI) for cattle and cold climates
INT <- INT %>% mutate(
  FWI = case_when(
    BW < 454 & DWI > PWI ~ DWI - PWI,
    BW < 454 & DWI < PWI ~ 0.1 * DWI,
    BW > 454 ~ 1.54 * DMI + 1.33 * 25.4 + 0.89 * DMFRAC + 0.58 * TEMP - 0.3 * RF - 25.65)) 

# ################## Daily Doses by matrix ###################################
# # Estimate daily dose from water 
INT <- INT %>% mutate(
  DW = FWI * mean_water_PFDA) 

# Estimate daily soil ingestion (based on DMI)
INT <- INT %>% mutate(
  SI = DMI * 0.04) 

INT <- INT %>% mutate(
  DS = SI * mean_soil_PFDA) 

# Estimate daily dose from milk intake
INT <- INT %>% mutate(
  DM = MY * milk_conc_PFDA)

# Estimate daily dose from grazing - based on dry matter intake
INT <- INT %>% mutate(
  DG = DMI * grass_conc_PFDA)

####################### Total Daily Dose ###################################

# Estimate total daily dose (water + soil + grass + milk)
INT <- INT %>% mutate(
  DI = DW + DS + DG + DM)

write.csv(INT,"2022_dose_PFDA.csv") #save dose output file

#######################################################################################
############################PFDA PopTK MODEL########################################
#### Single Compartment PK Model for Cattle uptake/elimination of PFDA with population model for stochastic simulations 
### Authors: Antti Mikkonen (UniSA/EPA VIC) and Barbara Astmann (MECDC)
## Version: 1.4

########################### Load libraries #######################################
library(deSolve) # package for solving differential equations
library(dplyr) # package for generating tidy datasets
library(ggplot2) #package for plotting
library(tidyr) #package for generating datasets
library(ggsci) # package for color palettes 
library(cowplot) # visualization package

################## Clear the workspace before starting #################################
rm(list=ls(all=TRUE))

######################################################################################### 
################################ PARAMETERS #############################################
### read in parameters table
## params based on metanalysis --> see supp materials

params <- read.csv("Parameter_table.csv") #Insert file path of 'Parameter_table.csv' file

### filter parameters for species and PFAS
means <- params %>% filter(Livestock == "Cattle", Analyte == "PFDA") %>% 
  dplyr::select(c(-1,-3,-5,-6)) %>%
  pivot_wider(names_from = Param, values_from = Value)

DT50 <- means$DT50
#DT50 <- means$DT50_lactating ## for dairy use "lactating" DT50
Vd <- means$Vd
PK <- means$PK
PL <- means$PL
PM <- means$PM
MW <- means$MW
Cgr <- means$Cgr
PMilk <- means$Pmilk 
Cgrs <- 0.27 

### pop variables

CV <- params %>% filter(Livestock == "Cattle", Analyte == "PFDA") %>%
  dplyr::select(c(-1,-3,-4,-5)) %>%
  pivot_wider(names_from = Param, names_glue = "{Param}_{.value}" , values_from = CV)

DT50_CV <- CV$DT50_CV
#DT50_lactating_CV <- CV$DT50_lactating_CV
Vd_CV <- CV$Vd_CV
PK_CV <- CV$PK_CV
PL_CV <- CV$PL_CV
PM_CV <- CV$PM_CV
PMilk_CV <- CV$Pmilk_CV

##############################################################################################
############################## EXPOSURE INPUTS ######################################################
###read in exposure data
#load only one data set at a time exp datasets are site specific

## Ledgerock
int <- read.csv("2022_dose_PFDA.csv") #Insert file path for dose output file generated at line 125

#Based on SWC models for daily cattle exposure to PFOS from drinking water and soil (exposure is 24h/day) 
#Define dose from exposure modelling (based on approxfun model)
# Filter exp for species
# int <- int %>%
#   filter(Species == "Cattle")

TIMEinf <- int$Days #times
AMTinf  <- int$DI #daily dose PFOS (sum of exposure from water and soil) ##### DICs for cattle and DISs for sheep
RATEinf <- AMTinf #daily dose to rate

DOSEinf <- data.frame(TIMEinf,RATEinf)

DOSEinf

#Define an interpolation function that retuns RATE when given TIME - "const" give step interpolation 
step.doseinf <- approxfun(TIMEinf, RATEinf, rule=2, method = "const") 

############################################################################################
#################### PopPK FUNCTION ########################################################

#>>>>>>>>>>>>>>>>>>>> Model equations <<<<<<<<<<<<<<<<<<<<<<<<<<<<

pop_pk <- function(Time, State, Parameters, runstochastic=F, seedvalue=1) {
  #print(state)
  with(as.list(c(State, Parameters)), {  # The with() function applies an expression to a dataset
    ##########################################################################################
    
    #Random effects ##### fist chunk is to add random variability to the population
    if(runstochastic == T) {
      set.seed(seedvalue)    #don't need a new set of random numbers unless a new individual is simulated
      ETA_DT50 <- rnorm(n=1, mean=0, sd=DT50_CV) 
      #ETA_DT50 <- rnorm(n=1, mean=0, sd=DT50_lactating_CV)  # 
      ETA_Vd <- rnorm(n=1, mean=0, sd=Vd_CV)  # 
      ETA_PM <- rnorm(n=1, mean=0, sd=PM_CV)  #
      ETA_PL <- rnorm(n=1, mean=0, sd=PL_CV)  #
      ETA_PMilk <- rnorm(n=1, mean=0, sd=PMilk_CV) #
      ETA_Dose <- rnorm(n=1, mean=0, sd=0.3) #### based on publications for intraspecies variability in water and diet intake
      #n.b. these ETA's may need to be correlated - can address this later
    } else {
      ETA_DT50 <- 0
      #ETA_DT50_lactating <- 0  #if modelling lactating cattle
      ETA_Vd <- 0
      ETA_PM <- 0
      ETA_PL <- 0
      ETA_PMilk <- 0
      ETA_Dose <- 0
    }
    
    #Time dependent variables
    days <- (Time)
    BW <- MW - MW*0.9*exp(-(Cgr*days)/MW^Cgrs) # based on CattleExplorer (Freer et al. 2012) regression equation
    DT50i <- DT50 * (BW/MW)**0.25 * exp(ETA_DT50) 
    #DT50i <- DT50_lactating * (BW/MW)**0.25 * exp(ETA_DT50)   #add lognormal variability
    Vdi <- Vd * BW * exp(ETA_Vd)  #add lognormal variability  # L --> Vdi is the estimated volume at time t (L/kg x kg = L)
    PMi <- PM * exp(ETA_PM)   #add variability
    PLi <- PL * exp(ETA_PL) #add variability
    PMilki <- PMilk * exp(ETA_PMilk) #add variability
    Dose <- step.doseinf(Time)
    Dosei <- Dose * exp(ETA_Dose)
    
    dADOSEoral = Dosei  # Amount ingested over whole exposure period (ug)
    
    # Central compartment
    RAC = (Dosei)-AC*(log(2)/DT50i) #rate of change in amount (ug) in central comp  
    dAC = RAC # amount in central compt at time t (ug)
    CC = AC/Vdi # conc. in central compartment at time t (ug/L)
    dAUCC = CC # area under the concentration time curve
    MC = CC*PMi # muscle conc. at time t
    LC = CC*PLi # liver conc. at time t
    MilkC = CC*PMilki # milk conc. at time t
    
    list(c(dADOSEoral, dAC, dAUCC), c("days"=days,"BW"=BW, "Vd"=Vdi, "Serum"=CC, "Muscle"=MC, "Liver"=LC, "Milk"=MilkC)) 
  })
}

########### Define State and Parameters for Function ####################################
#### State should be specific to site 
State <- c(ADOSEoral = 0, AC = 130, AUCC = 0) #### first run set states to zero then you can account for maternal transfer with AC 
##for maternal transfer for calf set AC to (based on 40% maternal transfer) 65 kg x 0.1 L/kg x 0.4 x 50 ug/L

Parameters <- c(DT50_CV, Vd_CV, PM_CV ,PL_CV, PMilk_CV, MW, Cgr, Cgrs, DT50, PM, PL, PMilk)

########### Time parameters ############################################################
starttime <- 0 
stoptime <- 779 #adjust for duration of simulation
dtout <- 1
Times <- seq(starttime, stoptime, dtout)

############ RUN FUNCTION and generate raw outputs ###################################### 

# Clear object that collects the results
pop_pkout <- NULL
# Number of runstochastic simulations
nsim <- 100

#Run a loop - each loop will sample different ETA values for the runstochastic simulation
for (i in 1:nsim) {
  
  out <- ode(y = State,
             times = Times, 
             func = pop_pk, 
             parms = Parameters,
             runstochastic = T,
             seedvalue = i,
             method = 'lsoda') 
  
  out <- as.data.frame(out) # coerces data into dataframe
  out <- cbind("sim"=i, out)
  
  pop_pkout <- rbind(pop_pkout, out) 
  
}

head(pop_pkout)

#################################################################################################
########### Make dataframe for plotting #########################################################
### from here on its all data visualization-modify per preference
#data structured for ggplot 

#serum and muscle (adjust if just modeling serum or muscle)
pop_pkout_long <- pop_pkout %>%
  gather(key = "parameter", value = "value", -time, -sim) %>%
  filter(parameter %in% c("Serum", "Muscle")) %>%  #this is used to gather results 
  mutate(sim = as.factor(sim)) %>%
  mutate(parameter = factor(parameter, levels = c("Serum","Muscle"))) 

### data summary
summary <- pop_pkout_long %>%
  group_by(parameter,time) %>%
  summarise(
    mean = mean(value),
    q10 = quantile(x=value, probs = 0.1),
    q25 = quantile(x=value, probs = 0.25),
    q50 = quantile(x=value, probs = 0.50),
    q75 = quantile(x=value, probs = 0.75),
    q100 = quantile(x=value, probs = 1.0))

write.csv(summary, "summary_PFDA.csv") 

### add health based criteria to dataframe --> adding to dataframe allows for facetted plotting
## run one based on compound and species modelled
#Maine Action Level for PFOS in Beef = 3.4 ppb, EU Maximum Limit for PFOS in beef=0.3 ppb

pop_pkout_long1 <- pop_pkout_long %>%
  mutate(MAL = case_when(
    parameter == "Muscle" ~ 3.4)) %>%
  mutate(EU_ML = case_when(
    parameter == "Muscle" ~ 0.3))

pop_pkout_long2 <- pop_pkout_long1 %>%
  pivot_longer(cols = c(MAL, EU_ML), names_to = "Criteria", values_to = "criteria_value")

###### Add vertical lines for seasons ########################
#2022
season_definition_cattle <- data.frame(
  Season = c("Summer", "Autumn", "Winter", "Spring", "Summer", "Autumn", "Winter", "Spring"),
  from = c(0.15, 0.40, 0.65, 0.9, 1.15, 1.4, 1.65, 1.9)) %>%
  mutate(labely = max(pop_pkout_long$value)+ 150)

###### Add serum data from site ###############################
## site and scenario specific 
## 2022
meas_serum <- read.csv("2022_Biomonitoring.csv") %>%
  filter(analyte == "PFDA") %>%
  filter(group == "2022") %>%
  mutate(parameter = factor(parameter, levels = c("Serum","Muscle"))) 

### define manual shapes and fills for monitoring data and static model estimate 
shaps <- c("Serum" = 21, "Muscle" = 24) ### , "Liver" = 22, "Muscle" = 24

################################################################################################
############## Make figures  ###################################################################
 # Run one at a time and to make figures with multiple plots re-run models for other compounds or mitigation scenarios  
         
#2022
P2 <- ggplot(pop_pkout_long) +
 geom_line(aes(x = time/365, y = value, colour = parameter, group=sim)) +
#stat_summary(aes(x = time/365, y = value), fun=median, geom="line", colour="black", lwd=1) +
#geom_line(aes(x = time/365, y = criteria_value, linetype = Criteria)) +
#geom_hline(data = hline.PFOS_EU, aes(yintercept = Z, linetype=factor(parameter))) + #, col = 'red' , linetype='dashed'
geom_vline(xintercept = season_definition_cattle$from, lty = 5, alpha = 0.3) + #_yearling
geom_text(data = season_definition_cattle, aes(x=from, y=labely, label = Season), angle = 90, vjust = 1, hjust = 1, alpha = 0.5) + #_yearling
#annotate(geom = "text", x = season_definition_cattle$from, y = season_definition_cattle$labely, label = season_definition_cattle$Season, angle = 90, vjust = 1, hjust = 1, alpha = 0.5) +
geom_jitter(data = meas_serum, aes(x = time/365, y = value, shape = parameter), size =4, alpha = 0.5, fill = "#DC0000B2",color = "black", width = 0.005, height = 0.001) +
stat_summary(aes(x = time/365, y = value), fun=median, geom="line", colour="black", lwd=1) +
scale_y_log10(limits = c(0.1,300)) + ## limits for B1 limits = c(0.1,3000)
facet_grid(~parameter) +
theme_bw() +
theme(legend.position = "bottom") +
labs(shape = expression(paste("Meas conc."))) +
labs(fill = expression(paste("Static model estimate"))) +
scale_shape_manual(values=shaps, labels = c("Serum", "Muscle")) + #labels = NULL ## , "liver", "muscle"
guides(colour = "none") + #fill = "none", shape = "none", linetype = "none"
labs(linetype = "Criteria") +
labs(title = "PFDA distribution in cattle - 2022", 
      x = "Time (years)",
      y = "PFDA ng/mL or ng/g")
         
P2
         
#save figures as jpeg       
ggsave(filename = "insert file name.jpeg", plot = P2, width = 10, height = 5, units = "cm", scale = 2.5) 

         
