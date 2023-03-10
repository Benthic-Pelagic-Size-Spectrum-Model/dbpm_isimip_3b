
library(tidyverse)
library(raster)
library(sf)
library(rnaturalearth)
library(patchwork)
library(lubridate)

mollCRS <- CRS("+proj=moll +lon_0=0 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs")
mollCRS_no <- 54009

robCRS <- CRS("+proj=robin +lon_0=0 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs")
robCRS_no <- 54030

lonlatCRS <- CRS("+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs")
lonlatCRS_no <- 4326

plotGlobalChange <- function(all, tit, w_sf, clim){
  
  # if history and future are given together 
  if(length(all)>1){
    x <- all$hist 
    y = all$fut 
  }else{ 
    x <- all$hist
  }
  
  if(length(all)>1){
    if(output == "annual"){
      out <- calc(x[[refFirstYear:(refFirstYear+10)]], mean)
    }else{
      out <- calc(x[[refFirstYear:(refFirstYear+10*12)]], mean) # Average 1990-1999 *12 if model resolution is months  
    }
    out <- addLayer(out, calc(y[[refLastYear:dim(y)[3]]], mean)) #  Average last decade
    x_change <- ((out[[2]] - out[[1]])/out[[1]]) * 100
  }else{
    if(output == "annual"){
      out <- calc(x[[refFirstYear:(refFirstYear+10)]], mean)
    }else{
      out <- calc(x[[refFirstYear:(refFirstYear+10*12)]], mean) # as above  
    }
    out <- addLayer(out, calc(x[[refLastYear:dim(x)[3]]], mean)) 
    x_change <- ((out[[2]] - out[[1]])/out[[1]]) * 100
  }
  
  dat <- st_as_sf(rasterToPolygons(x_change))
  dat <- st_transform(dat, crs = st_crs(robCRS)) # Convert to Robinson Projection
  
  gg <- ggplot() +
    geom_sf(data = dat, aes(fill = layer), colour = NA) +
    geom_sf(data = w_sf, size = 0.05, fill = "grey20") +
    scale_fill_gradient2(name = "Biomass Change (%)",
                         limits = clim,
                         midpoint = 0,
                         low = "red",
                         mid = "white",
                         high = "royalblue1",
                         position = "right",
                         na.value = "grey80",
                         guide = "colourbar",
                         oob = scales::squish) +
    ggtitle(tit) +
    scale_x_continuous(expand = c(0, 0)) +
    scale_y_continuous(expand = c(0, 0)) +
    theme(
      legend.title = element_text(angle = -90),
      panel.background = element_blank(),
      title = element_text(size = 15),
      legend.key.height = unit(0.8, "cm"),
      legend.title.align = 0.5) +
    guides(fill = guide_colourbar(title.position = "right"))
  
  return(gg)
}

plotGlobalYear <- function(dat, tit, w_sf){
  
  # CN trial 
  # dat<-fut[[(86*12)-2]]
  # w_sf = world_sf
  
  names(dat) <- "layer"
  dat <- st_as_sf(rasterToPolygons(dat)) %>%
    st_transform(crs = st_crs(robCRS)) # %>% # Convert to Robinson Projection
  # mutate(layer = log10(layer/1e3)) # Convert to kg
  
  gg <- ggplot() +
    geom_sf(data = dat, aes(fill = layer), colour = NA) +
    geom_sf(data = w_sf, size = 0.05, fill = "grey20") +
    scale_fill_gradient(name = expression("Total Biomass (g m"^-2*")"), # (log"[10]*"(kg m"^-2*"))"),
                        limits = c(quantile(dat$layer, .10), quantile(dat$layer, .90)),
                        low = "yellow",
                        high = "red",
                        position = "right",
                        na.value = "grey80",
                        guide = "colourbar",
                        oob = scales::squish) +
    ggtitle(tit) +
    scale_x_continuous(expand = c(0, 0)) +
    scale_y_continuous(expand = c(0, 0)) +
    theme(legend.title = element_text(angle = -90),
          panel.background = element_blank(),
          title = element_text(size = 8),
          legend.key.height = unit(1, "cm"),
          legend.title.align = 0.5) +
    guides(fill = guide_colourbar(title.position = "right"))
  
  return(gg)
}

plotTimeseries <- function(all, tit){
  
  if(length(all)>1){
    out <- stack(all$hist, all$fut) 
  }else{
    out <- all$hist
  }

  df <- as.data.frame(out, xy = TRUE) #%>%
  
  # fix columns as dates (needed for DBPM, not sure for the other models ...)
  date = as.character(date)
  colnames(df)<-c("x","y",date)
  
  df<-pivot_longer(df,!c(x,y), names_to = "Date", values_to = "Biomass") 
  
  df<-mutate(df, Date = ymd(Date),
             Year = year(Date),
             Month = month(Date))
  
  # explore last dot point for DBPM - why so high biomass?????? nove outside the function here
  # a<-filter(df, Year == 2100, Month %in% c(10,11,12))
  # a<-filter(a, y == 89.5)
  # head(a)
  # a$Biomass
  # df<-filter(df, Date < "2100-12-01") # done already outside function
  # explore NA or 1e20 values 
  # trial <- filter(df, Year == 2011, 
  #                 Month  == 10, 
  #                 is.na(Biomass))
  # nrow(trial) # should be 23473 (land - OK)
  # filter years - already done outside function
  # df2<-filter(df2, Year>=1950) # for consistency with Zoom 
  
  df2 <- df %>%
    group_by(Year) %>%
    summarise(Biomass = median(Biomass, na.rm = TRUE)) #,
  # .groups = "keep") #  not sure what this is 
  
  # CN adding  - make it as Lotze et al 
  # consider only 1971 owards (Boats starts in 1971...) and calcualte changes from 1990-1999 decade 
  df2<- filter(df2, Year>1970)
  refDecade <- df2 %>% 
    filter(Year >= 1990, Year <=2000)
  refDecade<-mean(refDecade$Biomass, na.rm = TRUE)
  
  # This doesn't seem to work in mutate. It just returns 0
  df2$BiomassChange = (df2$Biomass - refDecade)/refDecade * 100
  
  # CN use line below if you consider all years and do the mean over first decade 
  # df2$BiomassChange = (df2$Biomass - mean(df2$Biomass[1:10], na.rm = TRUE))/mean(df2$Biomass[1:10], na.rm = TRUE) * 100
  
  gg <- ggplot(data = df2, aes(x = Year, y = BiomassChange)) +
    geom_line() +
    #ylim(-5,3)+
    geom_smooth(method = "lm") +
    ggtitle(tit) +
    theme_bw() +
    theme(title = element_text(size = 8)) +
    ylab("Total Biomass Change (%)")
  
  rm(out)
  
  return(gg)
}

# Download and process world outline
world <- ne_countries(scale = "medium", returnclass = "sf")
world_sf <- st_transform(world, crs = st_crs(robCRS)) # Convert to different CRS

