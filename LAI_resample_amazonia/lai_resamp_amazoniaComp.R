##

# Resampling Copernicus Land Products (https://land.copernicus.eu/; CLP) at 333m to 1km resolution and assessment of 
# different methodologies.
# CLP are projected in a standard WGS84 projection (also known as the Plate Carrée projection) with the latitude and 
# longitude coordinates defined at the pixel centre (1km pixel is 1/112º). This implies that the pixel boundaries 
# extend ± 1/224º for both latitude and longitude at the pixel corners. 
# 300m-products pixels are 1/336º, therefore 1km-prdoducts are 3 x 3 300m-products. 
# However, users should note that due to the pixel coordinate definition (which applies to both 1km and 300m), no 
# proper aggregation of 300m to 1km can be performed at the minimum and maximum latitude and longitude, while such
# an aggregation can be done within these boundaries
# (http://proba-v.vgt.vito.be/sites/proba-v.vgt.vito.be/files/products_user_manual.pdf).


## Settings
#rm(list = ls())
#.rs.restartR()
library(ncdf4)
library(fields)
library(raster)
library(rgdal)
library(lattice)
library(sf)
library(plotrix)

if(Sys.info()[4] == "D01RI1700371"){
  path2data <- "E:/rotllxa/lai_resample/lai_data"
  path2save <- ""
}else if(Sys.info()[4] == "h05-wad.ies.jrc.it"){
  path2data <- ""
  path2save <- ""
}else if(Sys.info()[4] == "MacBook-MacBook-Pro-de-Xavier.local"){
  path2data <- "/Users/xavi_rp/Documents/D6_LPD/NDVI_data"
  path2save <- "/Users/xavi_rp/Documents/D6_LPD/NDVI_resample/LAI_resample_amazonia"
}else{
  stop("Define your machine before to run LPD")
}

setwd(path2save)

nc_file300m <- paste0(path2data, "/lai300_v1_333m/lai300_v1_333m_c_gls_LAI300_201905100000_GLOBE_PROBAV_V1.0.1.nc")
lai_1km_orig <- paste0(path2data, "/lai_v2_1km/c_gls_LAI-RT6_201905100000_GLOBE_PROBAV_V2.0.1.nc")



## Amazonian working extent ####

my_extent <- extent(-70, -63, -5.5, -0.2)


# Checking correspondence with 1km PROBA-V products
# The following vectors contain Long and Lat coordinates, respectively, of the 1km grid (cell boundaries):
x_ext <- seq((-180 - ((1 / 112) / 2)), 180, (1/112))
y_ext <- seq((80 + ((1 / 112) / 2)), - 60, - (1/112))

if(!all(round(my_extent[1], 7) %in% round(x_ext, 7) &
        round(my_extent[2], 7) %in% round(x_ext, 7) &
        round(my_extent[3], 7) %in% round(y_ext, 7) &
        round(my_extent[4], 7) %in% round(y_ext, 7))){
  # The given extent from raster or coordinate vector does not fit into the 1km PROBA-V grid, so we are going to adjust it
  for(crd in 1:length(as.vector(my_extent))){
    if(crd <= 2){
      my_extent[crd] <- x_ext[order(abs(x_ext - my_extent[crd]))][1]
    }else{
      my_extent[crd] <- y_ext[order(abs(y_ext - my_extent[crd]))][1]
    }
  }
  print("'my_extent' coordinates have been adjusted")
}
as.vector(my_extent)


## Reading in data 1km global ####
lai_1km_orig <- raster(lai_1km_orig)
img_date <- lai_1km_orig@z[[1]]
lai_1km_orig_extnt <- extent(lai_1km_orig)

if(all(round(lai_1km_orig_extnt[1], 7) %in% round(x_ext, 7) &
       round(lai_1km_orig_extnt[2], 7) %in% round(x_ext, 7) &
       round(lai_1km_orig_extnt[3], 7) %in% round(y_ext, 7) &
       round(lai_1km_orig_extnt[4], 7) %in% round(y_ext, 7))){
  print("lai_1km_orig extent matches PROBA-V products")
}else{
  stop("lai_1km_orig extent does NOT match PROBA-V products!!!")
}   

#cropping to Amazonian test area
lai_1km_orig_Amaz <- crop(lai_1km_orig, my_extent)
as.vector(extent(my_extent))
as.vector(extent(lai_1km_orig_Amaz))
summary(getValues(lai_1km_orig_Amaz))

jpeg(paste0(path2save, "/lai_1km_orig_Amaz.jpg"))
plot(lai_1km_orig_Amaz, main = "lai_1km_orig_Amaz")
dev.off()

lai1km_rstr <- lai_1km_orig_Amaz


## Reading in data 300m ####
lai_300m_orig <- raster(nc_file300m)
lai_300m_orig_extnt <- extent(lai_300m_orig)

#cropping to Amazonian test area
lai_300m_orig_Amaz <- crop(lai_300m_orig, my_extent)
as.vector(extent(my_extent))
as.vector(extent(lai_300m_orig_Amaz))
summary(getValues(lai_300m_orig_Amaz))

jpeg(paste0(path2save, "/lai_300m_orig_Amaz.jpg"))
plot(lai_300m_orig_Amaz, main = "lai_300m_orig_Amaz")
dev.off()


if(all(round(extent(lai_300m_orig_Amaz)[1], 7) %in% round(x_ext, 7) &
       round(extent(lai_300m_orig_Amaz)[2], 7) %in% round(x_ext, 7) &
       round(extent(lai_300m_orig_Amaz)[3], 7) %in% round(y_ext, 7) &
       round(extent(lai_300m_orig_Amaz)[4], 7) %in% round(y_ext, 7))){
  print("lai_300m_orig_extnt extent matches PROBA-V products")
}else{
  stop("lai_300m_orig_extnt extent does NOT match PROBA-V products!!!")
}   


## Dealing with "flagged values" ####
# "flagged values" are those corresponding to water bodies, NAs, etc. 
# They have LAI values > cuttoff_NA_err (7.00), or assigned values in the NetCDF between 251 and 255.
# They have LAI values < cuttoff_NA_err_min (0.00), or assigned values in the NetCDF between 251 and 255.
# We might want to "remove" them from the average calculations as they are highly influencing such averages,
# driving to wrong predictions.

# Converting flagged values to NAs
lai300m_rstr <- lai_300m_orig_Amaz

cuttoff_NA_err <- 6.99993  # everything > cuttoff_NA_err, must be removed for the calculations
cuttoff_NA_err_min <- -0.000001  # everything <= cuttoff_NA_err_min, must be removed for the calculations

jpeg(paste0(path2save, "/lai1km_NA.jpg"))
#plot(lai1km_rstr, breaks = c(cuttoff_NA_err_min, minValue(lai1km_rstr), cuttoff_NA_err), col = c("white", "blue"))
plot(lai1km_rstr, breaks = c(-0.000001, minValue(lai300m_rstr), cuttoff_NA_err), col = c("red", "blue"))
dev.off()

jpeg(paste0(path2save, "/lai300m_NA.jpg"))
#plot(lai300m_rstr, breaks = c(cuttoff_NA_err_min, minValue(lai1km_rstr), cuttoff_NA_err), col = c("white", "blue"))
plot(lai300m_rstr, breaks = c(-0.000001, minValue(lai300m_rstr), cuttoff_NA_err), col = c("red", "blue"))
dev.off()


# 300m product
sum(is.na(as.data.frame(lai300m_rstr)))
sum(as.data.frame(lai300m_rstr) > cuttoff_NA_err, na.rm = TRUE)

lai300m_rstr[lai300m_rstr > cuttoff_NA_err] <- NA  # setting to NA
lai300m_rstr[lai300m_rstr < cuttoff_NA_err_min] <- NA  # setting to NA
sum(is.na(as.data.frame(lai300m_rstr)))

# 1km product
lai1km_rstr[lai1km_rstr > cuttoff_NA_err] <- NA   # setting to NA
lai1km_rstr[lai1km_rstr < cuttoff_NA_err_min] <- NA   # setting to NA
sum(is.na(as.data.frame(lai1km_rstr)))



## Resampling using aggregate() ####
mean_w.cond <- function(x, ...){ # mean including condition 'minimum 5 valid pixels'
  n_valid <- sum(!is.na(x)) # number of cells with valid value
  if(n_valid > 4){
    dts <- list(...)
    if(is.null(dts$na_rm)) dts$na_rm <- TRUE
    x_mean <- mean(x, na.rm = dts$na_rm)
    return(x_mean)
  }else{
    x_mean <- NA
    return(x_mean)
  }
}


aggr_method <- "mean"
aggr_method <- "mean_w.cond"
t0 <- Sys.time()
r300m_resampled1km_Aggr <- aggregate(lai300m_rstr,
                                     fact = 3, # from 333m to 1km  
                                     fun = aggr_method, 
                                     na.rm = TRUE, 
                                     filename = 'r300m_resampled1km_Aggr.tif',
                                     overwrite = TRUE)
Sys.time() - t0
#r300m_resampled1km_Aggr <- raster('r300m_resampled1km_Aggr.tif')
r300m_resampled1km_Aggr

# plotting resampled map
jpeg(paste0(path2save, "/r300m_resampled1km_Aggr.jpg"))
plot(r300m_resampled1km_Aggr, main = "r300m_resampled1km_Aggr")
dev.off()


# plotting original 1km and 300m
jpeg(paste0(path2save, "/lai1km_300m_Amaz.jpg"),
     width = 22, height = 14, units = "cm", res = 300)
par(mfrow = c(1, 2), mar = c(4, 4, 4, 5))
plot(lai1km_rstr, main = "LAI 1km")
plot(lai300m_rstr, main = "LAI 333m ") 
dev.off()


# plotting original-1km + resampled-1km
jpeg(paste0(path2save, "/lai1km_1kmResampled_RAggr.jpg"),
     width = 22, height = 14, units = "cm", res = 300)
par(mfrow = c(1, 2), mar = c(4, 4, 4, 5))
plot(lai1km_rstr, col = rev(terrain.colors(704))[-c(1:40)], 
     breaks = seq(0, 7, 0.01), 
     legend = FALSE,
     main = "LAI 1km (original)")
color.legend(-62, -6, -61.8, 0, as.character(seq(0, 7, 1)), 
             rev(terrain.colors(704))[-c(1:40)], gradient = "y", align = "rb")
plot(r300m_resampled1km_Aggr, col = rev(terrain.colors(704))[-c(1:40)], 
     breaks = seq(0, 7, 0.01), 
     legend = FALSE,
     main = "LAI 1km (resampled)") 
color.legend(-62, -6, -61.8, 0, as.character(seq(0, 7, 1)), 
             rev(terrain.colors(704))[-c(1:40)], gradient = "y", align = "rb")
dev.off()






## Resampling using resample() ####

#r300m_resampled1km_Bilinear <- resample(lai300m_rstr, lai1km_rstr, 
#                                        method = "bilinear", 
#                                        filename = paste0(path2save, "/r300m_resampled1km_Bilinear.tif"),
#                                        overwrite = TRUE)
#



## Comparison 'original-1km' with '300m-resampled-1km-R_Aggr' ####
comp_results <- as.data.frame(matrix(ncol = 4))  #to store results
names(comp_results) <- c("objects", 
                         "Pearson's r", "Root Mean Square Error", "Mean Absolute Error")
comp_results[1, 1] <- "orig-1km__resampl-1km-R-Aggreg"

rsmpl_df <- data.frame(getValues(lai1km_rstr), getValues(r300m_resampled1km_Aggr))

sum(complete.cases(rsmpl_df))
#rsmpl_df <- rsmpl_df[complete.cases(rsmpl_df), 1:2]

# Pearson's correlation coefficient
rsmpl_df_pearson <- cor(rsmpl_df[complete.cases(rsmpl_df), 1:2], method = "pearson")[2, 1]
rsmpl_df_pearson
rsmpl_df_pearson^2  # if we fit a linear regression (see below), this is R^2 (R squared)
comp_results[1, 2] <- rsmpl_df_pearson

# Plotting correlation (scatterplot)
perc_subsample <- 10   # percentage of points for plotting
num_subsample <- round((nrow(rsmpl_df) * perc_subsample / 100), 0)
smple <- sample(nrow(rsmpl_df), num_subsample)
rsmpl_df_subsample <- rsmpl_df[smple, ]

jpeg(paste0(path2save, "/resample_correlation_RAggr.jpg"))
xyplot(rsmpl_df_subsample$getValues.r300m_resampled1km_Aggr. ~ rsmpl_df_subsample$getValues.lai1km_rstr., 
       type = c("p", "r"),
       col.line = "red",
       xlab = "1km original lai product",
       ylab = "1km resampled lai image (R)",
       main = paste0("Pearson's r = ", as.character(round(rsmpl_df_pearson, 4))),
       sub = paste0("Plotting a random subsample of ", num_subsample, " (", perc_subsample, "%) points")
)
dev.off()


# Calculating differences (errors)
head(rsmpl_df)
rsmpl_df <- rsmpl_df[complete.cases(rsmpl_df), 1:2]
rsmpl_df$diff <- abs(rsmpl_df$getValues.lai1km_rstr. - rsmpl_df$getValues.r300m_resampled1km_Aggr.)
rsmpl_df$diff1 <- abs(round(rsmpl_df$getValues.lai1km_rstr., 1) - round(rsmpl_df$getValues.r300m_resampled1km_Aggr., 1))
rsmpl_df$diff3 <- abs(round(rsmpl_df$getValues.lai1km_rstr., 3) - round(rsmpl_df$getValues.r300m_resampled1km_Aggr., 3))

summary(rsmpl_df$diff)
summary(rsmpl_df$diff1)
quantile(rsmpl_df$diff1, seq(0, 1, 0.1))
summary(rsmpl_df$diff3) # not substantial differences with 'rsmpl_df$diff'


# Root Mean Square Error (RMSE; the lower, the better)
# In GIS, the RMSD is one measure used to assess the accuracy of spatial analysis and remote sensing.
rmse <- sqrt(mean((rsmpl_df$diff)^2)) 
comp_results[1, 3] <- rmse

# Mean Absolute Error (MAE; the lower, the better)
mae <- mean(rsmpl_df$diff)
comp_results[1, 4] <- mae

# Saving stuff for the report
stuff2save <- c("comp_results", "my_extent", "img_date")
save(list = stuff2save, file = paste0(path2save, "/ResampleResults_LAI_amazonia_4Report.RData"))
#load(paste0(path2save, "/ResampleResults_LAI_amazonia_4Report.RData"), verbose = TRUE)

## Mapping the largets errors ####
rsmpl_df <- data.frame(getValues(lai1km_rstr), getValues(r300m_resampled1km_Aggr))
rsmpl_df$diff <- abs(rsmpl_df$getValues.lai1km_rstr. - rsmpl_df$getValues.r300m_resampled1km_Aggr.)
round(quantile(rsmpl_df$diff, seq(0, 1, 0.1), na.rm = TRUE), 3)
perc95 <- round(as.vector(quantile(rsmpl_df$diff, c(0.95), na.rm = TRUE)), 3)
rsmpl_df$groups <- NA
rsmpl_df$groups[!is.na(rsmpl_df$getValues.lai1km_rstr.) |
                  !is.na(rsmpl_df$getValues.r300m_resampled1km_Aggr.)] <- "a"
rsmpl_df$groups[rsmpl_df$diff >= perc] <- "b"

# scatterplot
#perc_subsample <- 10   # percentage of points for plotting
#num_subsample <- round((nrow(rsmpl_df) * perc_subsample / 100), 0)
rsmpl_df_subsample <- rsmpl_df[smple, ]

#rsmpl_df_subsample$groups <- "a"
#rsmpl_df_subsample$groups[rsmpl_df_subsample$getValues.lai1km_rstr. > 5.2 &
#                            rsmpl_df_subsample$getValues.r300m_resampled1km_Aggr. < 4] <- "b"

#jpeg(paste0(path2save, "/resample_correlation_RAggr_largestErr.jpg"))
#xyplot(rsmpl_df_subsample$getValues.r300m_resampled1km_Aggr. ~ rsmpl_df_subsample$getValues.lai1km_rstr., 
#       type = c("p"),
#       groups = factor(rsmpl_df_subsample$groups, labels = c("Error < 95th Perc", "Error >= 95th Perc")),
#       auto.key = list(columns = 1),
#       xlab = "1km original lai product",
#       ylab = "1km resampled lai image (R)",
#       main = paste0("Pearson's r = ", as.character(round(rsmpl_df_pearson, 4))),
#       sub = paste0("Plotting a random subsample of ", num_subsample, " (", perc_subsample, "%) points")
#)
#dev.off()

# mapping
lai1km_rstr_errors <- lai1km_rstr
lai1km_rstr_errors <- setValues(lai1km_rstr_errors, as.matrix(as.numeric(round(rsmpl_df$diff, 3))))
lai1km_rstr_errors

jpeg(paste0(path2save, "/lai1km_1kmResampled_RAggr_LargerErrors.jpg"))
brks <- c( minValue(lai1km_rstr_errors), perc95, maxValue(lai1km_rstr_errors))
#perc95 <- round(as.vector(quantile(rsmpl_df$diff, c(0.95), na.rm = TRUE)), 3)
plot(lai1km_rstr_errors, col = c("blue", "red"), colNA = "grey88", 
     breaks = brks, 
     legend = FALSE,
     main = "Absolute Error:  |orig1km - resamp1km|  "#,
     #sub = paste0("95th percentile = ", perc95)
)
#legend("bottom", legend = paste0("Absolute Error: ", perc95, " to ", maxValue(lai1km_rstr_errors)),
#       fill = "red", inset = 0.02)
legend("bottom", 
       legend = c(paste0("Absolute Error >= ", perc95, " (95th Percentile)"), "NoData"),
       fill = c("red", "white"), inset = 0.005)
dev.off()





## Resampling using aggregate() / 95th percentile ####
quant_w.cond <- function(x, perc = 0.95, ...){ # mean including condition 'minimum 5 valid pixels'
  n_valid <- sum(!is.na(x)) # number of cells with valid value
  if(n_valid > 4){
    dts <- list(...)
    if(is.null(dts$na_rm)) dts$na_rm <- TRUE
    x_quant <- quantile(x, perc, na.rm = dts$na_rm)
    return(x_quant)
  }else{
    x_quant <- NA
    return(x_quant)
  }
}

aggr_method <- "quant_w.cond"
t0 <- Sys.time()
r300m_resampled1km_Aggr_quant <- aggregate(lai300m_rstr,
                                           fact = 3, # from 333m to 1km  
                                           fun = aggr_method, 
                                           na.rm = TRUE, 
                                           #filename = 'r300m_resampled1km_Aggr.tif',
                                           overwrite = TRUE
)
Sys.time() - t0
r300m_resampled1km_Aggr_quant
#r300m_resampled1km_Aggr <- r300m_resampled1km_Aggr_quant


rsmpl_df <- data.frame(getValues(lai1km_rstr), getValues(r300m_resampled1km_Aggr_quant))
rsmpl_df <- rsmpl_df[complete.cases(rsmpl_df), 1:2]

# Pearson's correlation coefficient
rsmpl_df_pearson <- cor(rsmpl_df, method = "pearson")[2, 1]
rsmpl_df_pearson
rsmpl_df_pearson^2  # if we fit a linear regression (see below), this is R^2 (R squared)
comp_results[2, 2] <- rsmpl_df_pearson

# Calculating differences (errors)
head(rsmpl_df)
rsmpl_df$diff <- abs(rsmpl_df$getValues.lai1km_rstr. - rsmpl_df$getValues.r300m_resampled1km_Aggr_quant.)

# Root Mean Square Error (RMSE; the lower, the better)
# In GIS, the RMSD is one measure used to assess the accuracy of spatial analysis and remote sensing.
rmse <- sqrt(mean((rsmpl_df$diff)^2)) 
comp_results[2, 3] <- rmse

# Mean Absolute Error (MAE; the lower, the better)
mae <- mean(rsmpl_df$diff)
comp_results[2, 4] <- mae

# Saving stuff for the report
comp_results[2, 1] <- "orig-1km__resampl-1km-R-Aggreg-Percentile95"

stuff2save <- c("comp_results", "my_extent", "img_date")
save(list = stuff2save, file = paste0(path2save, "/ResampleResults_LAI_amazonia_4Report.RData"))



## Resampling using aggregate() / 50th percentile (median) ####
quant_w.cond <- function(x, perc = 0.50, ...){ # mean including condition 'minimum 5 valid pixels'
  n_valid <- sum(!is.na(x)) # number of cells with valid value
  if(n_valid > 4){
    dts <- list(...)
    if(is.null(dts$na_rm)) dts$na_rm <- TRUE
    x_quant <- quantile(x, perc, na.rm = dts$na_rm)
    return(x_quant)
  }else{
    x_quant <- NA
    return(x_quant)
  }
}

aggr_method <- "quant_w.cond"
t0 <- Sys.time()
r300m_resampled1km_Aggr_quant <- aggregate(lai300m_rstr,
                                           fact = 3, # from 333m to 1km  
                                           fun = aggr_method, 
                                           na.rm = TRUE, 
                                           #filename = 'r300m_resampled1km_Aggr.tif',
                                           overwrite = TRUE
)
Sys.time() - t0
r300m_resampled1km_Aggr_quant
#r300m_resampled1km_Aggr <- r300m_resampled1km_Aggr_quant


rsmpl_df <- data.frame(getValues(lai1km_rstr), getValues(r300m_resampled1km_Aggr_quant))
rsmpl_df <- rsmpl_df[complete.cases(rsmpl_df), 1:2]

# Pearson's correlation coefficient
rsmpl_df_pearson <- cor(rsmpl_df, method = "pearson")[2, 1]
rsmpl_df_pearson
rsmpl_df_pearson^2  # if we fit a linear regression (see below), this is R^2 (R squared)
comp_results[3, 2] <- rsmpl_df_pearson

# Calculating differences (errors)
head(rsmpl_df)
rsmpl_df$diff <- abs(rsmpl_df$getValues.lai1km_rstr. - rsmpl_df$getValues.r300m_resampled1km_Aggr_quant.)

# Root Mean Square Error (RMSE; the lower, the better)
# In GIS, the RMSD is one measure used to assess the accuracy of spatial analysis and remote sensing.
rmse <- sqrt(mean((rsmpl_df$diff)^2)) 
comp_results[3, 3] <- rmse

# Mean Absolute Error (MAE; the lower, the better)
mae <- mean(rsmpl_df$diff)
comp_results[3, 4] <- mae

# Saving stuff for the report
comp_results[3, 1] <- "orig-1km__resampl-1km-R-Aggreg-Median"

stuff2save <- c("comp_results", "my_extent", "img_date")
save(list = stuff2save, file = paste0(path2save, "/ResampleResults_lai_amazonia_4Report.RData"))








## Comparison 'original-1km' with '300m-resampled-1km-QGIS_Aggr' ####
qgis_resamp_amazonia_avrge <- paste0(path2data, "/QGIS_CGLT/lai.tif")

qgis_resamp_amazonia_avrge <- raster(qgis_resamp_amazonia_avrge)

qgis_extent <- extent(qgis_resamp_amazonia_avrge)

# Checking correspondence with 1km PROBA-V products
# The following vectors contain Long and Lat coordinates, respectively, of the 1km grid (cell boundaries):
x_ext <- seq((-180 - ((1 / 112) / 2)), 180, (1/112))
y_ext <- seq((80 + ((1 / 112) / 2)), - 60, - (1/112))

if(all(round(qgis_extent[1], 7) %in% round(x_ext, 7) &
       round(qgis_extent[2], 7) %in% round(x_ext, 7) &
       round(qgis_extent[3], 7) %in% round(y_ext, 7) &
       round(qgis_extent[4], 7) %in% round(y_ext, 7))){
  print("qgis_resamp_amazonia_avrge extent matches PROBA-V products")
}else{
  stop("qgis_resamp_amazonia_avrge extent does NOT match PROBA-V products!!!")
}   

# Cropping 'qgis_resamp_amazonia_avrge'
qgis_resamp_amazonia_avrge <- crop(qgis_resamp_amazonia_avrge, my_extent)
qgis_resamp_amazonia_avrge

if(all(round(extent(qgis_resamp_amazonia_avrge)[1], 7) %in% round(x_ext, 7) &
       round(extent(qgis_resamp_amazonia_avrge)[2], 7) %in% round(x_ext, 7) &
       round(extent(qgis_resamp_amazonia_avrge)[3], 7) %in% round(y_ext, 7) &
       round(extent(qgis_resamp_amazonia_avrge)[4], 7) %in% round(y_ext, 7))){
  print("qgis_resamp_amazonia_avrge extent matches PROBA-V products")
}else{
  stop("qgis_resamp_amazonia_avrge extent does NOT match PROBA-V products!!!")
}   


comp_results[2, 1] <- "orig-1km__resampl-1km-QGIS-Aggreg"

rsmpl_df <- data.frame(getValues(lai1km_rstr), getValues(qgis_resamp_amazonia_avrge))
rsmpl_df <- rsmpl_df[complete.cases(rsmpl_df), 1:2]

# Pearson's correlation coefficient
rsmpl_df_pearson <- cor(rsmpl_df, method = "pearson")[2, 1]
comp_results[2, 2] <- rsmpl_df_pearson

# Plotting correlation (scatterplot)
#perc_subsample <- 1   # percentage of points for plotting
num_subsample <- round((nrow(rsmpl_df) * perc_subsample / 100), 0)
rsmpl_df_subsample <- rsmpl_df[sample(nrow(rsmpl_df), num_subsample), ]

jpeg(paste0(path2save, "/resample_correlation_QGISAggr.jpg"))
xyplot(rsmpl_df_subsample$getValues.qgis_resamp_amazonia_avrge. ~ rsmpl_df_subsample$getValues.lai1km_rstr., 
       type = c("p", "r"),
       col.line = "red",
       xlab = "1km original LAI product",
       ylab = "1km resampled LAI image (QGIS)",
       main = paste0("Pearson's r = ", as.character(round(rsmpl_df_pearson, 4))),
       sub = paste0("Plotting a random subsample of ", num_subsample, " (", perc_subsample, "%) points")
)
dev.off()


# Calculating differences (errors)
rsmpl_df$diff <- abs(rsmpl_df$getValues.lai1km_rstr. - rsmpl_df$getValues.qgis_resamp_amazonia_avrge.)
rsmpl_df$diff1 <- abs(round(rsmpl_df$getValues.lai1km_rstr., 1) - round(rsmpl_df$getValues.qgis_resamp_amazonia_avrge., 1))

# Root Mean Square Error (RMSE; the lower, the better)
# In GIS, the RMSD is one measure used to assess the accuracy of spatial analysis and remote sensing.
rmse <- sqrt(mean((rsmpl_df$diff)^2)) 
comp_results[2, 3] <- rmse

# Mean Absolute Error (MAE; the lower, the better)
mae <- mean(rsmpl_df$diff)
comp_results[2, 4] <- mae


# plotting original-1km + resampled-1km
jpeg(paste0(path2save, "/lai1km_1kmResampled_QGISAggr.jpg"),
     width = 22, height = 14, units = "cm", res = 300)
par(mfrow = c(1, 2), mar = c(4, 4, 4, 5))
plot(lai1km_rstr, main = "LAI 1km (original)")
plot(qgis_resamp_amazonia_avrge, main = "LAI 1km (resampled)") 
dev.off()




## Comparison '300m-resampled-1km-R_Aggr' with '300m-resampled-1km-QGIS_Aggr' ####
comp_results[3, 1] <- "resampl-1km-R-Aggreg__resampl-1km-QGIS-Aggreg"

rsmpl_df <- data.frame(getValues(r300m_resampled1km_Aggr), getValues(qgis_resamp_amazonia_avrge))
rsmpl_df <- rsmpl_df[complete.cases(rsmpl_df), 1:2]

# Pearson's correlation coefficient
rsmpl_df_pearson <- cor(rsmpl_df, method = "pearson")[2, 1]
comp_results[3, 2] <- rsmpl_df_pearson

# Plotting correlation (scatterplot)
#perc_subsample <- 1   # percentage of points for plotting
num_subsample <- round((nrow(rsmpl_df) * perc_subsample / 100), 0)
rsmpl_df_subsample <- rsmpl_df[sample(nrow(rsmpl_df), num_subsample), ]

jpeg(paste0(path2save, "/resample_correlation_R_QGIS_Aggr.jpg"))
xyplot(rsmpl_df_subsample$getValues.qgis_resamp_amazonia_avrge. ~ rsmpl_df_subsample$getValues.r300m_resampled1km_Aggr., 
       type = c("p", "r"),
       col.line = "red",
       xlab = "1km resampled LAI image (R)",
       ylab = "1km resampled LAI image (QGIS)",
       main = paste0("Pearson's r = ", as.character(round(rsmpl_df_pearson, 4))),
       sub = paste0("Plotting a random subsample of ", num_subsample, " (", perc_subsample, "%) points")
)
dev.off()


# Calculating differences (errors)
rsmpl_df$diff <- abs(rsmpl_df$getValues.r300m_resampled1km_Aggr. - rsmpl_df$getValues.qgis_resamp_amazonia_avrge.)
rsmpl_df$diff1 <- abs(round(rsmpl_df$getValues.r300m_resampled1km_Aggr., 1) - round(rsmpl_df$getValues.qgis_resamp_amazonia_avrge., 1))

# Root Mean Square Error (RMSE; the lower, the better)
# In GIS, the RMSD is one measure used to assess the accuracy of spatial analysis and remote sensing.
rmse <- sqrt(mean((rsmpl_df$diff)^2)) 
comp_results[3, 3] <- rmse

# Mean Absolute Error (MAE; the lower, the better)
mae <- mean(rsmpl_df$diff)
comp_results[3, 4] <- mae




# Saving stuff for the report
stuff2save <- c("comp_results", "my_extent", "img_date")
save(list = stuff2save, file = paste0(path2save, "/ResampleResults_LAI_amazonia_4Report.RData"))

comp_results[, 2:4] <- round(comp_results[, 2:4], 5)
write.csv(comp_results, "comp_results.csv")



