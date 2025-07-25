## Helper function for predict.
## Assert that we can use old model (data.tmb0) as basis for
## predictions using the new data (data.tmb1):
assertIdenticalModels <- function(data.tmb1, data.tmb0, allow.new.levels=FALSE) {
  ## Check terms. Only 'blockReps' and 'blockSize' are allowed to
  ## change.  Note that we allow e.g. spatial covariance matrices to
  ## change, while e.g. an unstrucured covariance must remain the
  ## same.
  checkTerms <- function(t1, t0) {
    ## Defensive check:
    stopifnot(identical(names(t1), names(t0)))
    ## *Never* allowed to differ:
    testIdentical <- function(checkNm) {
      unlist( Map( function(x,y)
        identical(x[checkNm], y[checkNm]), t0, t1) )
    }
    ok <- testIdentical( c("blockNumTheta", "blockCode") )
    if ( ! all(ok) ) {
      msg <- c("Prediction is not possible for terms: ",
               paste(names(t1)[!ok], collapse=", "), "\n",
               "Probably some factor levels in 'newdata' require fitting a new model.")
      stop(msg)
    }
    ## Sometimes allowed to differ:
    if ( ! allow.new.levels ) {
      ok <- testIdentical( c( "blockReps", "blockSize") )
      if ( ! all(ok) ) {
        msg <- c("Predicting new random effect levels for terms: ",
                 paste(names(t1)[!ok], collapse=", "), "\n",
                 "Disable this warning with 'allow.new.levels=TRUE'")
        ## FIXME: warning or error ?
        warning(msg)
      }
    }
  }
  checkTerms( data.tmb1$terms,   data.tmb0$terms )
  checkTerms( data.tmb1$termszi, data.tmb0$termszi )
  checkTerms( data.tmb1$termsdisp, data.tmb0$termsdisp )
  ## Fixed effect parameters must be identical
  checkModelMatrix <- function(X1, X0) {
    if( !identical(colnames(X1), colnames(X0)) ) {
      msg <- c("Prediction is not possible for unknown fixed effects: ",
               paste( setdiff(colnames(X1), colnames(X0)), collapse=", "), "\n",
               "Probably some factor levels in 'newdata' require fitting a new model.")
      stop(msg)
    }
  }
  ## get whichever of the model matrices is non-zero
  getX <- function(data,suffix="") {
    denseX <- data[[paste0("X",suffix)]]
    sparseX <- data[[paste0("X",suffix,"S")]]
    if (ncol(denseX)>0) denseX else sparseX
  }
  checkModelMatrix(getX(data.tmb1), getX(data.tmb0))
  checkModelMatrix(getX(data.tmb1,"zi"), getX(data.tmb0,"zi"))
  checkModelMatrix(getX(data.tmb1,"disp"), getX(data.tmb0,"disp"))
  NULL
}

##' prediction
##' @param object a \code{glmmTMB} object
##' @param newdata new data for prediction
##' @param newparams new parameters for prediction
##' @param se.fit return the standard errors of the predicted values?
##' @param cov.fit return the covariance matrix of the predicted values?                        
##' @param zitype deprecated: formerly used to specify type of zero-inflation probability. Now synonymous with \code{type}
##' @param type Denoting \eqn{mu} as the mean of the conditional distribution and
##' \code{p} as the zero-inflation probability,
##' the possible choices are:
##' \describe{
##' \item{"link"}{the linear predictor of the conditional model, or
##' equivalently the conditional mean on the scale of the link function
##' (this equivalence does not hold for truncated distributions, where
##' the link-scaled value is not adjusted for the effect of truncation on the mean; to get the corrected value of the conditional mean on the linear predictor
##' scale, use \code{family(m)$linkfun(predict(m, type = "conditional"))})}
##' \item{"response"}{expected value; this is \eqn{mu*(1-p)} for zero-inflated models
##' and \code{mu} otherwise}
##' \item{"conditional"}{mean of the conditional response; \code{mu} for all models
##' (i.e., synonymous with \code{"response"} in the absence of zero-inflation}
##' \item{"zprob"}{the probability of a structural zero (returns 0 for non-zero-inflated models)}
##' \item{"zlink"}{predicted zero-inflation probability on the scale of
##' the logit link function (returns \code{-Inf} for non-zero-inflated models)}
##' \item{"disp"}{dispersion parameter, however it is defined for that particular family (as described in  \code{\link{sigma.glmmTMB}})}
##' \item{"latent"}{return latent variables}
##' }
##' @param na.action how to handle missing values in \code{newdata} (see \code{\link{na.action}});
##' the default (\code{na.pass}) is to predict \code{NA}
##' @param debug (logical) return the \code{TMBStruc} object that will be
##' used internally for debugging?
##' @param aggregate (optional factor vector) sum the elements with matching factor levels
##' @param do.bias.correct (logical) should aggregated predictions use Taylor expanded estimate of nonlinear contribution of random effects (see details)
##' @param bias.correct.control a list sent to TMB's function \code{sdreport()}. See documentation there.
##' @param re.form \code{NULL} to specify individual-level predictions; \code{~0} or \code{NA} to specify population-level predictions (i.e., setting all random effects to zero)
##' @param allow.new.levels allow previously unobserved levels in random-effects variables? see details.
##' @param \dots unused - for method compatibility
##' @param fast predict without expanding memory (default is TRUE if \code{newdata} and \code{newparams} are NULL and population-level prediction is not being done)
##' @details
##' \itemize{
##' \item To compute population-level predictions for a given grouping variable (i.e., setting all random effects for that grouping variable to zero), set the grouping variable values to \code{NA}. Finer-scale control of conditioning (e.g. allowing variation among groups in intercepts but not slopes when predicting from a random-slopes model) is not currently possible.
##' \item Prediction of new random effect levels is possible as long as the model specification (fixed effects and parameters) is kept constant.
##' However, to ensure intentional usage, a warning is triggered if \code{allow.new.levels} is \code{NULL} (the default) and \code{re.form} is not NA, or if \code{allow.new.levels} is explicitly set to \code{TRUE}.
##' \item Prediction using "data-dependent bases" (variables whose scaling or transformation depends on the original data, e.g. \code{\link{poly}}, \code{\link[splines]{ns}}, or \code{\link{poly}}) should work properly; however, users are advised to check results extra-carefully when using such variables. Models with different versions of the same data-dependent basis type in different components (e.g. \code{formula= y ~ poly(x,3), dispformula= ~poly(x,2)}) will probably \emph{not} produce correct predictions.
##' \item Bias corrected predictions are based on the method described in Thorson J.T. & Kristensen (2016). These should be checked carefully by the user and are not extensively tested.
##' }
##' @references
##' Thorson J.T. & Kristensen K. (2016) Implementing a generic method for bias correction in statistical models using random effects, with spatial and population dynamics examples. \emph{Fish. Res.} 175, 66-74. 
##'
##'
##' @examples
##' data(sleepstudy,package="lme4")
##' g0 <- glmmTMB(Reaction~Days+(Days|Subject),sleepstudy)
##' predict(g0, sleepstudy)
##' ## Predict new Subject
##' nd <- sleepstudy[1,]
##' nd$Subject <- "new"
##' predict(g0, newdata=nd, allow.new.levels=TRUE)
##' ## population-level prediction
##' nd_pop <- data.frame(Days=unique(sleepstudy$Days),
##'                      Subject=NA)
##' predict(g0, newdata=nd_pop)
##' ## return latent variables (BLUPs/conditional modes/etc. ) with standard errors
##' ##  (actually conditional standard deviations)
##' predict(g0, type = "latent", se.fit = TRUE)
##' @importFrom TMB sdreport
##' @importFrom stats optimHess model.frame na.fail na.pass napredict contrasts<-
##' @export
predict.glmmTMB <- function(object,
                            newdata=NULL,
                            newparams=NULL,
                            se.fit=FALSE,
                            cov.fit=FALSE,
                            re.form=NULL,
                            allow.new.levels=NULL,
                            type = c("link", "response",
                                     "conditional", "zprob", "zlink",
                                     "disp", "latent"),
                            zitype = NULL,
                            na.action = na.pass,
                            fast=NULL,
                            debug=FALSE,
                            aggregate=NULL,
                            do.bias.correct=FALSE,
                            bias.correct.control = list(sd = TRUE),
                            ...) {
  ## FIXME: implement 'complete' re.form (e.g. identify elements of Z or b that need to be zeroed out)

  check_dots(..., .action = "warning")

  ## FIXME: better test? () around re.form==~0 are *necessary*
  ## could steal isRE from lme4 predict.R ...
  pop_pred <- (!is.null(re.form) && ((re.form==~0) ||
                                       identical(re.form,NA)))
  if (!(is.null(re.form) || pop_pred)) {
      stop("re.form must equal NULL, NA, or ~0")
  }
  
  allow.new.levels <- allow.new.levels %||% pop_pred

  if (cov.fit) {
    if (!se.fit) message("se.fit set to TRUE because cov.fit = TRUE")
    se.fit <- TRUE
  }
  
  if(is.null(aggregate)) {
    aggregate <- factor()
  }
  ## FIXME: add re.form
  
  if (length(aggregate) > 0) {
    fast <- FALSE
  }
  if (do.bias.correct) {
    se.fit <- TRUE
  }
  if (!is.null(zitype)) {
    warning("zitype is deprecated: please use type instead")
    type <- zitype
  }
  type <- match.arg(type)
  
  ## match type arg with internal name
  ## FIXME: warn if "link"
  ziPredNm <- switch(type,
                     response   = "corrected",
                     link       =,
                     conditional= "uncorrected",
                     zlink      = ,
                     zprob      = "prob",
                     disp       = "disp", #zi irrelevant; just reusing variable
                     latent     = "uncorrected",  ## ignored, but needs to have a legal value
                     stop("unknown type ",type))
  ziPredCode <- .valid_zipredictcode[ziPredNm]

  ## oldPar <- get_pars(object)
  oldPar <- object$fit$par
  if (!is.null(newparams)) oldPar <- newparams

  new_stuff <- !is.null(newdata) || !is.null(newparams) || pop_pred
  if (isTRUE(fast) && new_stuff) {
    stop("fast=TRUE is not compatible with newdata/newparams/population-level prediction")
  }

  if (is.null(fast)) fast <- !new_stuff

  ## what to ADREPORT:
  ## 0 = no pred; 1 = response scale; 2 = link scale; 3 = latent vars
  do_pred_val <- if (!se.fit) {  0
  } else if (type == "latent") {
    3
  } else if (!grepl("link",type)) {
    1
  } else 2

  na.act <- attr(model.frame(object),"na.action")
  do.napred <- missing(newdata) && !is.null(na.act)

  ## DRY: there is a little bit of repeated code here but didn't
  ## want to make a giant if-block
  ## ('goto' would be handy here ...)
  if (noZI(object) && type %in% c("zprob", "zlink")) {
    dd <- if (!is.null(newdata)) newdata else object$obj$env$data$Xdisp
    pred <- se <- setNames(numeric(nrow(dd)), rownames(dd))
    se[] <- NA_real_
    pred[] <- if (type == "zprob") 0 else -Inf
    if (do.napred) {
      pred <- napredict(na.act, pred)
      if (se.fit) se <- napredict(na.act,se)
    }
    if (cov.fit) covfit <- matrix(NA_real_, nrow = length(se.fit), ncol = length(se.fit), dimnames = list(names(se.fit), names(se.fit)))
    if (!se.fit) return(pred) else if (cov.fit) return(list(fit=pred, se.fit=se, cov.fit = covfit)) else return(list(fit=pred, se.fit=se))
  }

  if (fast) {
    ee <- environment(object$obj$fn)
    lp <- ee$last.par.best                 ## used in $report() call below
    dd <- ee$data         ## data object
    orig_vals <- dd[c("whichPredict", "doPredict", "ziPredictCode")]
    dd$whichPredict <- as.numeric(seq(nobs(object)))  ## replace 'whichPredict' entry
    if (se.fit) {
      dd$doPredict <- do_pred_val
    }
    dd$ziPredictCode <- ziPredCode
    assign("data",dd, ee) ## stick this in the appropriate environment
    newObj <- object$obj
    
    ## restore original values to environment of the object
    ## putting add=TRUE first would be more readable,
    ##  but that tickles a bug in R < 4.0.2
    on.exit(
      expr=    {
        for (i in names(orig_vals)) {
          dd[[i]] <- orig_vals[[i]]
          assign("data",dd, environment(object$obj$fn))
        }
      },
      add = TRUE)
    ## end of 'fast predict'
  }  else {

    mc <- mf <- object$call
    ## FIXME: DRY so much
    ## now work on evaluating model frame
    ## do we want to re-do this part???

    ## need to 'fix' call to proper model.frame call whether or not
    ## we have new data, because ... (??)
    m <- match(c("subset", "weights", "offset", "na.action"),
               names(mf), 0L)
    mf <- mf[c(1L, m)]

    mf$drop.unused.levels <- TRUE
    mf[[1]] <- as.name("model.frame")
    ## substitute *combined* data frame, in hopes of getting all of the
    ##  bits we need for any of the model frames ...
    tt <- terms(object$modelInfo$allForm$combForm)
    pv <- attr(terms(model.frame(object)),"predvars")
    ## get rid of response variable     
    attr(tt,"predvars") <- pv[-2] ## was: fix_predvars(pv,tt)
    mf$formula <- RHSForm(tt, as.form=TRUE)

    ## fix_predvars (in utils.R) is NO LONGER USED
    ## We now rely on the 'variables' and 'predvars' attributes matching
    ## up correctly, **except for the response variable**, from the
    ## terms of 'combForm' and the model frame, and working with whatever
    ## newdata= argument is provided.
    ## Passes existing tests/known cases.
    ## We should still be on the lookout for crazy/unforeseen
    ## usage of data-dependent bases (e.g. polynomials or splines with
    ## different arguments in different parts of the model ...)
    ## This could be further improved by making RHSForm()
    ##  use delete.response() -- handles dropping response from predvars
    ## Would still need careful testing etc..

    
    if (is.null(newdata)) {
      mf$data <- mc$data ## restore original data
      newFr <- object$frame
    } else {
      mf$na.action <- na.action
      if (pop_pred) {
        ## add missing components in newdata
        ## (placeholder only to avoid error in model frame construction:
        ##  value shouldn't matter since all b values will be fixed to NA anyway ...)
        req_vars <- all.vars(RHSForm(formula(object, reOnly = TRUE)))
        for (fnew in setdiff(req_vars, names(newdata))) {
          newdata[[fnew]] <- NA
        }
      }
      mf$data <- newdata
      newFr <- eval.parent(mf)
    }

    omi <- object$modelInfo  ## shorthand ("**o**bject$**m**odel**I**nfo")

    respCol <- match(respNm <- names(omi$respCol),names(newFr))
    ## create *or* overwrite response column for prediction data with NA
    newFr[[respNm]] <- NA

    ## FIXME: not yet handling population-level predictions (re.form
    ##  or new levels/allow.new.levels)

    ## append to existing model frame
    ## rbind loses attributes!
    ## https://stackoverflow.com/questions/46258816/copy-attributes-when-using-rbind
    ## at this point I'm not even sure if contrasts are actually *used*
    ## for anything in the prediction process: do mismatches even matter?
    safe_contrasts <- function(x) {
      if (length(levels(x))<2) return(NULL) else return(contrasts(x))
    }
    aug_contrasts <- function(c1, new_levels = NULL) {
      rbind(c1,
            matrix(0,
                   ncol=ncol(c1),
                   nrow=length(new_levels),
                   dimnames=list(new_levels,colnames(c1))))
    }

    augFr <- rbind(object$frame, newFr)
    facs <- which(vapply(augFr, is.factor, FUN.VALUE = logical(1)))
    ##  I believe all the machinery here is for resolving
    ##    https://github.com/glmmTMB/glmmTMB/issues/439

    fnms <- names(augFr)[facs]
    form <- formula(object)
    ## vars on LEFT side of (f|g) only
    re_vars <- unlist(lapply(findbars(form), function(x) all.vars(x[2][[1]])))
    nongrpvars <- union(all.vars(nobars(form)), re_vars)
    ## want to exclude factors that appear *only* in grpvars
    ## (== include vars from fixed effects and varying terms)
    fnms <- fnms[fnms %in% nongrpvars]
    
    for (fnm in fnms) {
      c1 <- safe_contrasts(object$frame[[fnm]])
      c2 <- safe_contrasts(newFr[[fnm]])
      if (!allow.new.levels) {
        ## subset contrasts to those relevant to newFr
        ## if rownames(c2) is NULL this won't do what we want ...
        if (!is.null(c2)) {
          row_ind <- rownames(c2) %||% seq_len(nrow(c2))
          c1_sub <- c1[row_ind, colnames(c2), drop=FALSE]
          ## maybe too coarse, but as mentioned above, I don't
          ##  even know if such mismatches really matter ...
          if(!(isTRUE(all.equal(c1_sub,c2)) ||
                 isTRUE(all.equal(c1, c2)))) {
            warning("contrasts mismatch between original and prediction frame in variable ",
                    sQuote(fnm))
          }
        } ## !is.null(c2)
      } ## !allow.new.levels
      ## DON'T check for contrasts mismatch with new levels
      ##   (hope we don't miss anything important!)
      ## what do we do here?
      ## the new levels aren't actually going to get used for anything,
      ##  but they break the contrast construction. Extend the contrast
      ##  matrix with a properly labeled zero matrix.
      if (!is.null(c1)) {
        new_levels <- stats::na.omit(setdiff(unique(newFr[[fnm]]),levels(object$frame[[fnm]])))
        contrasts(augFr[[fnm]]) <- aug_contrasts(c1,new_levels)
      }
    }

    ## Pointers into 'new rows' of augmented data frame.
    w <- nrow(object$fr) + seq_len(nrow(newFr))

    ## Variety of possible binomial inputs are taken care of by
    ## 'mkTMBStruc' further down.
    yobs <- augFr[[names(omi$respCol)]]

    ## extract smooth information
    ## NULL if missing
    old_smooths <- lapply(omi$reTrms, function(x) x[["smooth_info"]])

    ## need eval.parent() because we will do eval(mf) down below ...
    TMBStruc <-
      ## FIXME: make first arg of mkTMBStruc into a formula list
      ## with() interfering with eval.parent() ?
      eval.parent(mkTMBStruc(RHSForm(omi$allForm$formula,as.form=TRUE),
                             omi$allForm$ziformula,
                             omi$allForm$dispformula,
                             omi$allForm$combForm,
                             mf,
                             fr=augFr,
                             yobs=yobs,
                             respCol=respCol,
                             ## need to strip attributes
                             weights=c(model.weights(augFr)),
                             contrasts=omi$contrasts,
                             family=omi$family,
                             ziPredictCode=ziPredNm,
                             doPredict=do_pred_val,
                             whichPredict=w,
                             aggregate=aggregate,
                             REML=omi$REML,
                             map=omi$map,
                             sparseX=omi$sparseX,
                             old_smooths = old_smooths,
                             ## don't need priors when predicting ...
                             priors = NULL)
                  )

    ## drop rank-deficient columns if necessary
    for (nm in c("", "zi", "disp")) {
      xnm <- paste0("X", nm)
      betanm <- paste0("beta", nm)
      X <- getME(object, xnm)
      has_dropped <- prod(dim(X)) > 0 && !is.null(dd <- attr(X, "col.dropped"))
      if (is(X, "Matrix")) xnm <- paste0(xnm, "S")
      newX <- TMBStruc$data.tmb[[xnm]]
      already_dropped <- ncol(newX) == ncol(X) && !any(names(dd) %in% colnames(newX))
      if (has_dropped && !already_dropped) {
        TMBStruc$data.tmb[[xnm]] <- TMBStruc$data.tmb[[xnm]][,-dd]
        TMBStruc$parameters[[betanm]] <- TMBStruc$parameters[[betanm]][-dd]
      }
    }

    ## short-circuit
    if(debug) return(TMBStruc)

    ## Check that the model specification is unchanged:
    assertIdenticalModels(TMBStruc$data.tmb,
                          object$obj$env$data, allow.new.levels)

    ## Check that the necessary predictor variables are finite (not NA nor NaN)
    if (se.fit) {
      with(TMBStruc$data.tmb, if(any(!is.finite(X)) |
                                   any(!is.finite(Z@x)) |
                                   any(!is.finite(Xzi)) |
                                   any(!is.finite(Zzi@x)) |
                                   any(!is.finite(Xdisp))
                                 ) stop("Some variables in newdata needed for predictions contain NAs or NaNs.
           This is currently incompatible with se.fit=TRUE or cov.fit=TRUE."))
    }

    ## FIXME: what if newparams only has a subset of components?

    if (!is.null(maparg <- TMBStruc$mapArg)) {
      full_pars <- get_pars(object, unlist=FALSE)
      for (i in names(maparg)) {
        mapind <- which(is.na(maparg[[i]]))
        if (length(mapind)>0) {
          TMBStruc$parameters[[i]][mapind] <- full_pars[[i]][mapind]
        }
      }
    }

    if (pop_pred) {

      ## use re.form, ll. 749ff of utils.R to decide which
      ##  b values to set to zero.  OK to map _all_ values in this case
      ##  (unless they're in newparams) ?
      TMBStruc <- within(TMBStruc, {
        parameters$b[] <- 0
        mapArg$b <- factor(rep(NA,length(parameters$b)))
      })
    }

    n_orig <- do.call(openmp, object$modelInfo$parallel)
    if (openmp_debug()) {
      cat("predict: setting OpenMP threads to ", n_orig, " on exit\n")
    }
    on.exit(do.call(openmp, n_orig), add = TRUE)

    newObj <- with(TMBStruc,
                   MakeADFun(data.tmb,
                             parameters,
                             map = mapArg,
                             random = randomArg,
                             profile = NULL, # TODO: Optionally "beta"
                             silent = TRUE,
                             DLL = "glmmTMB"))
    newObj$fn(oldPar)  ## call once to update internal structures
    lp <- newObj$env$last.par

  }  ## NOT fast

  ## set TMB threads to value from original model fit/reset on exit
  ## FIXME: OpenMP reporting is not quite right
  ## n = 1L rather than NULL so we report "setting" rather than "current"
  ## autopar switches from NULL to FALSE (default)  
  parallel <- object$modelInfo$parallel
  if (!all(sapply(parallel, is.null))) {
    n_orig <- openmp()
    do.call(openmp, parallel)
    on.exit(do.call(openmp, n_orig), add = TRUE)
  }


  if (openmp_debug()) {
    cat("TMB threads currently set to ", openmp(NULL), "\n")
  }
  return_par <- if (type %in% c("zlink", "link")) "eta_predict" else if (type=="latent") "b" else "mu_predict"

  if (!se.fit) {
    rr <- newObj$report(lp)
    pred <- rr[[return_par]]
  } else {
    H <- with(object,optimHess(oldPar,obj$fn,obj$gr))
    ## FIXME: Eventually add 'getReportCovariance=FALSE' to this sdreport
    ##        call to fix memory issue (requires recent TMB version)
    ## Fixed! (but do we want a flag to get it ? ...)
    if (cov.fit) {
      sdr <- sdreport(newObj,oldPar,hessian.fixed=H,getReportCovariance=TRUE)
      covfit <- sdr$cov
    } else     sdr <- sdreport(newObj,oldPar,hessian.fixed=H,getReportCovariance=FALSE,bias.correct=do.bias.correct,bias.correct.control=bias.correct.control)

    sdrsum <- summary(sdr, "report") ## TMB:::summary.sdreport(sdr, "report")
    ## split summary matrix by parameter name
    sdrsplit <- split.data.frame(sdrsum, rownames(sdrsum))
    pred <- sdrsplit[[return_par]][,"Estimate"]
    se <- sdrsplit[[return_par]][,"Std. Error"]
    w <- which(rownames(sdrsum) == return_par)
    if (cov.fit) covfit <- covfit[w, w]
    
    if (do.bias.correct) {
      return (sdrsum[w,])
    }
  }
  if (do.napred) {
    pred <- napredict(na.act,pred)
    if (se.fit) se <- napredict(na.act,se)
    if (cov.fit) {
      tmp <- covfit
      covfit <- matrix(NA_real_, nrow = length(se.fit), ncol = length(se.fit), dimnames = list(names(se.fit), names(se.fit)))
      covfit[!is.na(covfit)] <- as.vector(tmp)
    }
  }
  if (!se.fit) return(pred) else if (cov.fit) return(list(fit=pred, se.fit=se, cov.fit = covfit)) else return(list(fit=pred, se.fit=se))
}
