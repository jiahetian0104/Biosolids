# regresstion slope soil concentration (Cs) and biosolids loading rate
regression_df <- data.frame(
  PFAS = c("PFHxA", "PFHpA", "PFOA", "PFNA", "PFDA", "PFHxS", "PFOS"),
  Regression_Slope = c(0.003, 0.003, 0.015, 0.003, 0.009, 0.004, 0.198)
)

# slope between Cwmax and Cs
cwmax_slope_df <- data.frame(
  PFAS = c("PFHxA", "PFHpA", "PFOA", "PFNA", "PFDA", "PFHxS", "PFOS"),
  Site_K = c(174.71, 94, 128.45, 54.3, 14.1, 56.8, 11.34),
  Site_W = c(131.31, 79.468, 101.39, 59.08, NA, 23.2, 8.09)
)

# define a calculation function
calculate_Cwmax <- function(pfas, C_0, biosolids_loading_rate, site = c("Site_K", "Site_W")) {
  site <- match.arg(site)
  
  slope_row <- regression_df[regression_df$PFAS == pfas, ]
  cwmax_row <- cwmax_slope_df[cwmax_slope_df$PFAS == pfas, ]
  
  if (nrow(slope_row) == 0 || nrow(cwmax_row) == 0) {
    stop("Invalid PFAS name provided.")
  }
  
  # C_S (ng/g), 
  C_S <- C_0 + slope_row$Regression_Slope * biosolids_loading_rate
  
  # slope between Cwmax and Cs
  m <- cwmax_row[[site]]
  
  if (is.na(m)) {
    stop(paste("No data for", pfas, "at", site))
  }
  
  # calculate C_wmax
  C_wmax <- m * C_S
  return(C_wmax)
}

# Example: calculate PFOS at Site_K, biosolids loading rate = 50 Mg/ha
# Result: C_w,max = 112.266 ng/L 
calculate_Cwmax("PFOS", C_0 = 2, biosolids_loading_rate = 50, site = "Site_K")
calculate_Cwmax("PFOS", C_0 = 0, biosolids_loading_rate = 50, site = "Site_K")

calculate_Cwmax("PFOA", biosolids_loading_rate = 50, site = "Site_W")



# Load error function (erf), derived from the normal distribution function
erf <- function(x) 2 * pnorm(x * sqrt(2)) - 1

# Function to calculate diluted concentration based on source concentration and dispersion parameters
calculate_diluted_concentration <- function(C0, x, Y, delta_gw, alpha_y, alpha_z) {
  # Check for valid positive input values to avoid division by zero or negative roots
  if (x <= 0 || alpha_y <= 0 || alpha_z <= 0) {
    stop("x, alpha_y, and alpha_z must be positive values.")
  }
  
  # Calculate lateral and vertical dispersion terms using the error function
  erf_y <- erf(Y / (4 * sqrt(alpha_y * x)))         # Lateral dilution
  erf_z <- erf(delta_gw / (2 * sqrt(alpha_z * x)))  # Vertical dilution
  
  # Compute dilution attenuation factor (DAF)
  DAF <- 1 / (erf_y * erf_z)
  
  # Calculate the diluted concentration at point (x)
  C <- C0 / DAF
  
  # Return both the diluted concentration and DAF
  return(list(C = C, DAF = DAF))
}




# Input parameters
C0 <- 112.77       # Initial concentration at the source (e.g., from C_wmax), in ng/L
x <- 10            # Distance from the source in the groundwater flow direction, in meters
Y <- 5             # Width of the source area perpendicular to flow, in meters
delta_gw <- 2      # Thickness of the groundwater mixing zone, in meters
alpha_y <- 0.5     # Lateral dispersivity, in meters
alpha_z <- 0.1     # Vertical dispersivity, in meters

# Run the calculation
result <- calculate_diluted_concentration(C0, x, Y, delta_gw, alpha_y, alpha_z)

# View the results
print(result)
