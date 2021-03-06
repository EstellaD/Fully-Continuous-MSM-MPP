# Ploting Based on Which Model Track
long_Y_cb_create <- data.frame(
  study_id = rep(unique(long_Y_cb$study_id), each = 365),
  Start = rep(0:364, length(unique(long_Y_cb$study_id))),
  End = rep(1:365, length(unique(long_Y_cb$study_id))),
  cycle = rep(rep(1:73, each = 5), length(unique(long_Y_cb$study_id)))
)

long_Y_cb_create <- long_Y_cb_create %>%
  full_join(subset(D0_gender, select = -c(D0, age, sex)), by="study_id")

long_Y_cb_create$timebasis_epi <- bs(long_Y_cb_create$End, Boundary.knots=c(0,tlim), degree = 2)

# Now map the treatment indicator from exposure data set
long_Y_cb_create <- long_Y_cb_create %>%     # only sampled patients
  inner_join(V_gender[, c("study_id", "cycle", "Dtrt", "yt")], by = c("study_id", "cycle")) %>%
  rename(A = Dtrt) %>%
  mutate(daily = 
           case_when(A == '1' ~ 5, 
                     A == '2' ~ 10, 
                     A == '3' ~ 20, 
                     A == '4' ~ 34, 
                     A == '5' ~ 50, 
                     A == '0' ~ 0))

# Initial cumdose so far
cum_init <- long_Y_cb %>%
  group_by(study_id) %>%
  filter(row_number() == 1) %>%
  dplyr::select(study_id, gccumdose) %>%
  rename(cumdose = gccumdose)
  
long_Y_cb_create <- long_Y_cb_create %>%
  full_join(cum_init) %>%
  group_by(study_id) %>%
  mutate(gccumdosesofar = cumsum(daily),
         gccumdose_projection = cumdose + gccumdosesofar,
         gccumdose = lag(gccumdose_projection)) %>%
  mutate(gccumdose = ifelse(is.na(gccumdose), cumdose, gccumdose))

long_Y_cb_create$gccumdosescale <- long_Y_cb_create$gccumdose - mean(long_Y_cb$cumdose) # deduct the same centred mean for PO dataset
rangecumdscale <- range(long_Y_cb_create$gccumdosescale)
long_Y_cb_create$timebasis_cumdosescale <- bs(long_Y_cb_create$gccumdosescale,
                                              Boundary.knots = c(rangecumdscale[1], rangecumdscale[2]), degree = 2)

long_Y_cb_create$futime <- long_Y_cb$futime[1]
########################## Potential Outcome Hazard Plot ###########################
# Initial cumdose so far
cum_init <-  long_Y_cb%>%
  group_by(study_id) %>%
  filter(row_number() == 1) %>%
  dplyr::select(study_id, gccumdose) %>%
  rename(cumdose = gccumdose)


### Create PO Data Sets
get_PO_df <- function(long_Y_cb, cum_init, D, daily){
  long_Y_cbd <- subset(long_Y_cb, select = c(-gccumdose))
  long_Y_cbd$Dtrt <- as.factor(D); 
  long_Y_cbd$Dtrtp <- as.factor(D); 
  long_Y_cbd$D0 <- as.factor(D); 
  long_Y_cbd$A <- as.factor(D); 
  long_Y_cbd$daily <- daily
  long_Y_cbd <- long_Y_cbd %>%
    full_join(cum_init)%>%
    group_by(study_id) %>%
    mutate(gccumdoseinterval = daily * End, 
           gccumdose_projection = cumdose + gccumdoseinterval, 
           gccumdose = lag(gccumdose_projection)) %>%
    mutate(gccumdose = ifelse(is.na(gccumdose), cumdose, gccumdose))
  
  # Already factorize discrete, because from long_Y_cb
  # Center new cont. var
  long_Y_cbd$gccumdosescale <- long_Y_cbd$gccumdose - mean(long_Y_cb$gccumdose) # deduct the same centered mean for PO dataset
  long_Y_cbd$timebasis_epi <- bs(long_Y_cbd$End, Boundary.knots=c(0, tlim), degree = 2) # it's the same as long_Y_cb
  rangecumdscale <- range(long_Y_cbd$gccumdosescale)
  long_Y_cbd$timebasis_cumdosescale <- bs(long_Y_cbd$gccumdosescale, 
                                          Boundary.knots=c(rangecumdscale[1], rangecumdscale[2]), degree = 2)
  return(long_Y_cbd)
}


long_Y_cbd1 <- get_PO_df(long_Y_cb, cum_init, 1, 5)
long_Y_cbd2 <- get_PO_df(long_Y_cb, cum_init, 2, 10)
long_Y_cbd3 <- get_PO_df(long_Y_cb, cum_init, 3, 20)
long_Y_cbd4 <- get_PO_df(long_Y_cb, cum_init, 4, 34)
long_Y_cbd5 <- get_PO_df(long_Y_cb, cum_init, 5, 50)



## PO plotting dataset
get_PO_haz_plt_df <- function(hazd1, hazd2, hazd3, hazd4, hazd5, End, stepsize){
  df <- as.data.frame(cbind(hazd1, hazd2, hazd3, hazd4, hazd5, End))
  df <- df %>%
    arrange(End)%>% 
    mutate(index = c(1:length(End)))
  
  cutoff <- head(seq(0,365, by=stepsize), -1)
  lab <- NULL
  for(i in 1:length(cutoff)){
    lab[i] <- which(df$End > cutoff[i])[1]
  }
  length(lab); head(lab); vec <- lab-lag(lab); min(vec[-1])
  
  df$tp <- ifelse(df$index %in% lab, 'a', 1)
  df$tp <- cumsum(df$tp == 'a'); df$tp <- as.factor(df$tp)
  df <- subset(df, select = -index)
  
  dfsum <- df %>%
    group_by(tp) %>%
    summarise(medianhazd1 = quantile(hazd1, probs = 0.50),
              medianhazd2 = quantile(hazd2, probs = 0.50),
              medianhazd3 = quantile(hazd3, probs = 0.50),
              medianhazd4 = quantile(hazd4, probs = 0.50),
              medianhazd5 = quantile(hazd5, probs = 0.50))
  
  dfplt <- dfsum %>%
    mutate(step = stepsize) %>%
    mutate(step = cumsum(step))
  
  df0 <- data.frame(
    tp='0',
    medianhazd1=0.0,
    medianhazd2=0.0,
    medianhazd3=0.0,
    medianhazd4=0.0,
    medianhazd5=0.0,
    step = 0)
  
  dfplt <- rbind(df0, as.data.frame(dfplt))
  
  return(dfplt)
}


## PO graph
plot_PO_haz_over_time <- function(female, whichmodel, dfplt, gender.name){
  if(female){
    pdf(paste0('/users/edong/Output/Female/Outcome/POhazovertime_female ', 
               str_replace_all(whichmodel, fixed(" "), ""), '.pdf'), width=8, height=8)
  }else{
    pdf(paste0('/users/edong/Output/Male/Outcome/POhazovertime_male', 
               str_replace_all(whichmodel, fixed(" "), ""), '.pdf'), width=8, height=8) 
  }
  
  range(subset(dfplt, select = -c(tp, step)))
  if(female){
    yrange=c(0, 0.044)
  }else{
    yrange=c(0, 0.032)
  }
  plot(dfplt$step, dfplt$medianhazd1, ylim = yrange, yaxt= 'n',lwd=2, type='s',
       lty=1, col = 1, 
       main = paste0('Estimated Potential Fracture Hazards Across Always Treated With \n Each Dose Levels Over Time With ', whichmodel,  ' - ', gender.name),
       xlab='Days since start of follow-up', ylab='Potential hazard of fracture')
  lines(dfplt$step, dfplt$medianhazd2, type = 's', lty=1, col=2, lwd=1.2)
  lines(dfplt$step, dfplt$medianhazd3, type = 's', lty=1, col=3, lwd=1.2)
  lines(dfplt$step, dfplt$medianhazd4, type = 's', lty=1, col=4, lwd=1.2)
  lines(dfplt$step, dfplt$medianhazd5, type = 's', lty=1, col=5, lwd=1.2)
  axis(side = 2, at = seq(yrange[1], yrange[2], length.out=5), 
       labels = round(seq(yrange[1], yrange[2], length.out=5),3))
  legend('topright', c("A = 1: daily dose = 5mg", 
                       "A = 2: daily dose = 10mg", 
                       "A = 3: daily dose = 20mg",
                       "A = 4: daily dose = 34mg", 
                       "A = 5: daily dose = 50mg"), cex = 0.8, 
         col=c(1:5), lty=rep(1, 5), lwd=1.5)
  dev.off()
}

POhaz_track <- function(model, long_Y_cbd1, long_Y_cbd2, long_Y_cbd3, long_Y_cbd4, long_Y_cbd5,
                        long_Y_cb, stepsize, female, whichmodel, gender.name){
  hazd1_which <- predict(model, newdata = long_Y_cbd1, type = 'response')
  hazd2_which <- predict(model, newdata = long_Y_cbd2, type = 'response')
  hazd3_which <- predict(model, newdata = long_Y_cbd3, type = 'response')
  hazd4_which <- predict(model, newdata = long_Y_cbd4, type = 'response')
  hazd5_which <- predict(model, newdata = long_Y_cbd5, type = 'response')
  
  dfplt_which <- get_PO_haz_plt_df(hazd1_which, hazd2_which, hazd3_which, hazd4_which, hazd5_which, 
                                   long_Y_cb$End, stepsize)
  plot_PO_haz_over_time(female, whichmodel, dfplt_which, gender.name)
}


## Plot PO Hazard Over Time
if(!is.na(whichmodel) & whichmodel == 'Dose Level Model'){
  POhaz_track(cbout.sw.slm.a, long_Y_cbd1, long_Y_cbd2, long_Y_cbd3, long_Y_cbd4, long_Y_cbd5,
              long_Y_cb, stepsize, female, whichmodel, gender.name)
  
}else if(!is.na(whichmodel) & whichmodel == 'Cumulative Dose Model'){
  POhaz_track(cbout.sw.slm.cumd, long_Y_cbd1, long_Y_cbd2, long_Y_cbd3, long_Y_cbd4, long_Y_cbd5,
              long_Y_cb, stepsize, female, whichmodel, gender.name)
  
}else if(!is.na(whichmodel) & whichmodel == 'Flexible Cumulative Dose Model'){
  POhaz_track(cbout.sw.slm.spcumd, long_Y_cbd1, long_Y_cbd2, long_Y_cbd3, long_Y_cbd4, long_Y_cbd5,
              long_Y_cb, stepsize, female, whichmodel, gender.name)
  
}else if(is.na(whichmodel)){
  POhaz_track(cbout.sw.slm.a, long_Y_cbd1, long_Y_cbd2, long_Y_cbd3, long_Y_cbd4, long_Y_cbd5,
              long_Y_cb, stepsize, female, 'Dose Level Model', gender.name)
  POhaz_track(cbout.sw.slm.cumd, long_Y_cbd1, long_Y_cbd2, long_Y_cbd3, long_Y_cbd4, long_Y_cbd5,
              long_Y_cb, stepsize, female, 'Cumulative Dose Model', gender.name)
  POhaz_track(cbout.sw.slm.spcumd, long_Y_cbd1, long_Y_cbd2, long_Y_cbd3, long_Y_cbd4, long_Y_cbd5,
              long_Y_cb, stepsize, female, 'Flexible Cumulative Dose Model', gender.name)
}





