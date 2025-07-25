
stopifnot(require("testthat"),
          require("glmmTMB"))

## drop (unimportant) info that may not match across versions
drop_version <- function(obj) {
    obj$modelInfo$packageVersion <- NULL
    obj$modelInfo$family$initialize <- NULL  ## updated initialization expressions
    obj$modelInfo$parallel <- NULL   ## parallel component changed from int to list
}

expect_equal_nover <- function(x,y,...) {
    expect_equal(drop_version(x),
                 drop_version(y),
                 ...)
}

## loaded by gt_load() in setup_makeex.R, but need to do this
##  again to get it to work in devtools::check() environment (ugh)
gm0 <- up2date(gm0)
gm1 <- up2date(gm1)

data(sleepstudy, cbpp,
     package = "lme4")

data(quine, package="MASS")

## n.b. for test_that, this must be assigned within the global
## environment ...

cbpp <<- transform(cbpp, prop = incidence/size, obs=factor(seq(nrow(cbpp))))

## utility: hack/replace parts of the updated result that will
##  be cosmetically different
matchForm <- function(obj, objU, family=FALSE, fn = FALSE) {
  for(cmp in c("call","frame")) # <- more?
      objU[[cmp]] <- obj[[cmp]]
  ## Q: why are formulas equivalent but not identical?  A: their environments may differ
  objU$modelInfo$allForm <- obj$modelInfo$allForm
  nm <- names(objU$modelInfo)
  objU$modelInfo$packageVersion <- packageVersion("glmmTMB")
  if (family)  objU$modelInfo$family <- obj$modelInfo$family
  ## objective function/gradient may change between TMB versions
  if (fn)  {
      for (f in c("fn","gr","he","retape","env","report","simulate")) {
          objU$obj[[f]] <- obj$obj[[f]]
      }
  }
  return(objU)
}


lm0 <- lm(Reaction~Days,sleepstudy)
fm00 <- glmmTMB(Reaction ~ Days, sleepstudy)
fm0 <- glmmTMB(Reaction ~ 1    + ( 1  | Subject), sleepstudy)
fm1 <- glmmTMB(Reaction ~ Days + ( 1  | Subject), sleepstudy)
fm2 <- glmmTMB(Reaction ~ Days + (Days| Subject), sleepstudy)
fm3 <- glmmTMB(Reaction ~ Days + ( 1  | Subject) + (0+Days | Subject),
               sleepstudy)

test_that("Basic Gaussian Sleepdata examples", {
    expect_is(fm00, "glmmTMB")
    expect_is(fm0, "glmmTMB")
    expect_is(fm1, "glmmTMB")
    expect_is(fm2, "glmmTMB")
    expect_is(fm3, "glmmTMB")

    expect_equal(fixef(fm00)[[1]],coef(lm0),tol=1e-5)
    expect_equal(sigma(fm00)*sqrt(nobs(fm00)/(df.residual(fm00)+1)),
                 summary(lm0)$sigma,tol=1e-5)
    expect_equal(fixef(fm0)[[1]], c("(Intercept)" = 298.508), tolerance = .0001)
    expect_equal(fixef(fm1)[[1]], c("(Intercept)" = 251.405, Days = 10.4673),
                 tolerance = .0001)
    expect_equal(fixef(fm2)$cond, fixef(fm1)$cond, tolerance = 1e-5)# seen 1.042 e-6
    expect_equal(fixef(fm3)$cond, fixef(fm1)$cond, tolerance = 5e-6)# seen 2.250 e-7

    expect_equal(head(ranef(fm0)$cond$Subject[,1],3),
                 c(37.4881849228705, -71.5589277273216, -58.009085500647),
                 tolerance=1e-5)
    ## test *existence* of summary method -- nothing else for now
    expect_is(suppressWarnings(summary(fm3)),"summary.glmmTMB")
})

test_that("Update Gaussian", {
  skip_on_cran()
  ## call doesn't match (formula gets mangled?)
  ## timing different
  fm1u <- update(fm0, . ~ . + Days)
  expect_equal_nover(fm1, matchForm(fm1, fm1u, fn=TRUE))
})


test_that("Variance structures", {
  skip_on_cran()
  ## above: fm2     <- glmmTMB(Reaction ~ Days +     (Days| Subject), sleepstudy)
  expect_is(fm2us   <- glmmTMB(Reaction ~ Days +   us(Days| Subject), sleepstudy), "glmmTMB")
  expect_is(fm2cs   <- glmmTMB(Reaction ~ Days +   cs(Days| Subject), sleepstudy), "glmmTMB")
  expect_is(fm2diag <- glmmTMB(Reaction ~ Days + diag(Days| Subject), sleepstudy), "glmmTMB")
  expect_equal(getME(fm2,  "theta"),
               getME(fm2us,"theta"))
  ## FIXME: more here, compare results against lme4 ...
})

test_that("Sleepdata Variance components", {
    expect_equal(c(unlist(VarCorr(fm3))),
                 c(cond.Subject = 584.247907378213, cond.Subject.1 = 33.6332741779585),
                 tolerance=1e-5)
})

test_that("Basic Binomial CBPP examples", {
    ## Basic Binomial CBPP examples ---- intercept-only fixed effect
    expect_is(gm0, "glmmTMB")
    expect_is(gm1, "glmmTMB")
    expect_equal(fixef(gm0)[[1]], c("(Intercept)" = -2.045671), tolerance = 1e-3)#lme4 results
    expect_equal(fixef(gm1)[[1]], c("(Intercept)" = -1.398343,#lme4 results
                               period2 = -0.991925, period3 = -1.128216,
                               period4 = -1.579745),
                  tolerance = 1e-3) # <- TODO: lower eventually

})

test_that("Multiple RE, reordering", {
    ### Multiple RE,  reordering
     skip_on_cran()
    tmb1 <- glmmTMB(cbind(incidence, size-incidence) ~ period + (1|herd) + (1|obs),
                    data = cbpp, family=binomial())
    tmb2 <- glmmTMB(cbind(incidence, size-incidence) ~ period + (1|obs) + (1|herd),
                    data = cbpp, family=binomial())
    expect_equal(fixef(tmb1), fixef(tmb2),                   tolerance = 1e-8)
    expect_equal(getME(tmb1, "theta"), getME(tmb2, "theta")[c(2,1)], tolerance = 5e-7)
})

test_that("Alternative family specifications [via update(.)]", {
    ## intercept-only fixed effect

    res_chr <- matchForm(gm0, update(gm0, family= "binomial"), fn  = TRUE)
    if (getRversion() >= "4.3.3") {
        ## mysterious failure on windows/oldrel (4.3.2)
        expect_equal_nover(gm0, res_chr)
        expect_equal_nover(gm0, matchForm(gm0, update(gm0, family= binomial()), fn = TRUE))
        expect_warning(res_list <- matchForm(gm0, update(gm0, family= list(family = "binomial",
                                                                           link = "logit")),
                                             family=TRUE, fn=TRUE))
        expect_equal_nover(gm0, res_list)
    }
})

test_that("Update Binomial", {
    ## matchForm(): call doesn't match (formula gets mangled?)
    ## timing different
    if (getRversion() >= "4.3.3") {
        gm1u <- update(gm0, . ~ . + period)
        expect_equal_nover(gm1, matchForm(gm1, gm1u, fn=TRUE), tolerance = 5e-8)
    }
})

test_that("internal structures", {
  ## RE terms in cond, zi, and disp model
  expect_equal(names(fm0$modelInfo$reTrms),
               c("cond","zi", "disp"))
})

test_that("close to lme4 results", {
    skip_on_cran()
    expect_true(require("lme4"))
    L <- load(system.file("testdata", "lme-tst-fits.rda",
                          package="lme4", mustWork=TRUE))
    expect_is(L, "character")
    message("Loaded testdata from lme4:\n ",
            paste(strwrap(paste(L, collapse = ", ")),
                  collapse = "\n "))

    if(FALSE) { ## part of the above [not recreated here for speed mostly:]
        ## intercept only in both fixed and random effects
        fit_sleepstudy_0 <- lmer(Reaction ~   1  + ( 1 | Subject), sleepstudy)
        ## fixed slope, intercept-only RE
        fit_sleepstudy_1 <- lmer(Reaction ~ Days + ( 1 | Subject), sleepstudy)
        ## fixed slope, intercept & slope RE
        fit_sleepstudy_2 <- lmer(Reaction ~ Days + (Days|Subject), sleepstudy)
        ## fixed slope, independent intercept & slope RE
        fit_sleepstudy_3 <- lmer(Reaction ~ Days + (1|Subject)+ (0+Days|Subject), sleepstudy)

        cbpp$obs <- factor(seq(nrow(cbpp)))
        ## intercept-only fixed effect
        fit_cbpp_0 <- glmer(cbind(incidence, size-incidence) ~ 1 + (1|herd),
                            cbpp, family=binomial)
        ## include fixed effect of period
        fit_cbpp_1 <- update(fit_cbpp_0, . ~ . + period)
        ## include observation-level RE
        fit_cbpp_2 <- update(fit_cbpp_1, . ~ . + (1|obs))
        ## specify formula by proportion/weights instead
        fit_cbpp_3 <- update(fit_cbpp_1, incidence/size ~ period + (1 | herd), weights = size)

    }

    ## What we really want to compare against - Maximum Likelihood (package 'DESCRIPTION' !)
    fi_0 <- lmer(Reaction ~   1  + ( 1  | Subject), sleepstudy, REML=FALSE)
    fi_1 <- lmer(Reaction ~ Days + ( 1  | Subject), sleepstudy, REML=FALSE)
    fi_2 <- lmer(Reaction ~ Days + (Days| Subject), sleepstudy, REML=FALSE)
    fi_3 <- lmer(Reaction ~ Days + (1|Subject) + (0+Days|Subject),
                 sleepstudy, REML=FALSE)

    ## Now check closeness to lme4 results

    ## ......................................
})

context("trickier examples")

data(Owls)
## is <<- necessary ... ?
Owls <- transform(Owls,
                   ArrivalTime=scale(ArrivalTime,center=TRUE,scale=FALSE),
                   NCalls= SiblingNegotiation)

test_that("basic zero inflation", {
       skip_on_cran()
       if(require("pscl")) {
	o0.tmb <- glmmTMB(NCalls~(FoodTreatment + ArrivalTime) * SexParent +
                              offset(logBroodSize),
                          ziformula=~1, data = Owls,
                          family=poisson(link = "log"))
	o0.pscl <-zeroinfl(NCalls~(FoodTreatment + ArrivalTime) * SexParent +
        offset(logBroodSize)|1, data = Owls)
    expect_equal(summary(o0.pscl)$coefficients$count, summary(o0.tmb)$coefficients$cond, tolerance=1e-5)
    expect_equal(summary(o0.pscl)$coefficients$zero, summary(o0.tmb)$coefficients$zi, tolerance=1e-5)

    o1.tmb <- glmmTMB(NCalls~(FoodTreatment + ArrivalTime) * SexParent +
        offset(logBroodSize) + diag(1 | Nest),
        ziformula=~1, data = Owls, family=poisson(link = "log"))
	expect_equal(ranef(o1.tmb)$cond$Nest[1,1], -0.484, tolerance=1e-2) #glmmADMB gave -0.4842771
       }
       })

test_that("alternative binomial model specifications", {
    skip_on_cran()
    d <<- data.frame(y=1:10,N=20,x=1) ## n.b. global assignment for testthat
    m0 <- suppressWarnings(glmmTMB(cbind(y,N-y) ~ 1, data=d, family=binomial()))
    m3 <- glmmTMB(y/N ~ 1, weights=N, data=d, family=binomial())
    expect_equal(fixef(m0),fixef(m3))
    m1 <- glmmTMB((y>5)~1,data=d,family=binomial)
    m2 <- glmmTMB(factor(y>5)~1,data=d,family=binomial)
    expect_equal(c(unname(logLik(m1))),-6.931472,tol=1e-6)
    expect_equal(c(unname(logLik(m2))),-6.931472,tol=1e-6)

})

test_that("formula expansion", {
              ## test that formulas are expanded in the call/printed
              form <- Reaction ~ Days + (1|Subject)
              expect_equal(grep("Reaction ~ Days",
                       capture.output(print(glmmTMB(form, sleepstudy))),
            fixed=TRUE),1)
})

test_that("NA handling", {
    skip_on_cran()
    data(sleepstudy,package="lme4")
    ss <- sleepstudy
    ss$Days[c(2,20,30)] <- NA
    op <- options(na.action=NULL)
    expect_error(glmmTMB(Reaction~Days,ss),"missing values in object")
    op <- options(na.action=na.fail)
    expect_error(glmmTMB(Reaction~Days,ss),"missing values in object")
    expect_equal(unname(fixef(glmmTMB(Reaction~Days,ss,na.action=na.omit))[[1]]),
                 c(249.70505,11.11263),
                 tolerance=1e-6)
    op <- options(na.action=na.omit)
    expect_equal(unname(fixef(glmmTMB(Reaction~Days,ss))[[1]]),
                 c(249.70505,11.11263),
                 tolerance=1e-6)
})

test_that("quine NB fit", {
    skip_on_cran()
    quine.nb1 <- MASS::glm.nb(Days ~ Sex/(Age + Eth*Lrn), data = quine)
    quine.nb2 <- glmmTMB(Days ~ Sex/(Age + Eth*Lrn), data = quine,
                         family=nbinom2())
    expect_equal(coef(quine.nb1),fixef(quine.nb2)[["cond"]],
                 tolerance=1e-4)
})
## quine.nb3 <- glmmTMB(Days ~ Sex + (1|Age), data = quine,
##                     family=nbinom2())

test_that("contrasts arg", {
    skip_on_cran()
    quine.nb1 <- MASS::glm.nb(Days ~ Sex*Age, data = quine,
                              contrasts=list(Sex="contr.sum",Age="contr.sum"))
    quine.nb2 <- glmmTMB(Days ~ Sex*Age, data = quine,
                         family=nbinom2(),
                         contrasts=list(Sex="contr.sum",Age="contr.sum"))
    expect_equal(coef(quine.nb1),fixef(quine.nb2)[["cond"]],
                 tolerance=1e-4)
})

test_that("zero disp setting", {
    skip_on_cran()
    set.seed(101)
    dd <- data.frame(y=rnorm(100),obs=1:100)
    m0 <- glmmTMB(y~1, data=dd)
    v0 <- sigma(m0)^2
    m1 <- glmmTMB(y~1+(1|obs), data=dd)
    tmpf <- function(x) c(sigma(x)^2, c(VarCorr(x)[["cond"]]$obs))
    m <- -log10(.Machine$double.eps^(1/4))
    pvec <- c(1,2.5,m,2*m,10)
    res <- matrix(NA,ncol=2,nrow=length(pvec), dimnames = list(format(pvec, digits = 3), c("sigma^2", "cond_var")))
    for (i in (seq_along(pvec))) {
        mz <- update(m1,dispformula=~0,
                     control=glmmTMBControl(zerodisp_val=log(10^(-pvec[i]))))
        res[i,] <- tmpf(mz)
    }
    res <- rbind(res,tmpf(m1))
    ## sum of residual variance and RE variance should be approx constant/independent of fixed sigma
    expect_true(var(res[,1]+res[,2])<1e-8)
})

test_that("dollar/no data arg warning", {
    expect_warning(glmmTMB(Reaction ~ sleepstudy$Days, data = sleepstudy),
                   "is not recommended")
    attach(sleepstudy)
    expect_warning(glmmTMB(Reaction ~ Days), "is recommended")
    op <- options(warn = 2)
    ## check that warning is suppressed
    expect_is(glmmTMB(Reaction ~ Days, data = NULL), "glmmTMB")
    detach(sleepstudy)
    options(op)
})

test_that("double bar notation", {
    data("sleepstudy", package="lme4")
    m1 <- glmmTMB(Reaction ~ 1 + (Days || Subject), sleepstudy)
    expect_equal(c(VarCorr(m1)$cond$Subject),
                 c(564.340387730194, 0, 0, 140.874101713108),
                 tolerance = 1e-6)
})

test_that("bar/double-bar bug with gaussian response", {
  set.seed(1)
  n <- 100
  xdata <- data.frame(
      rfac1 = as.factor(sample(letters[1:10], n, replace = TRUE)),
      rfac2 = as.factor(sample(letters[1:10], n, replace = TRUE)),
      cov = rnorm(n),
      rv = rpois(n, lambda = 2)
  )
  m2 <- glmmTMB(rv~cov+(1+cov||rfac1)+(1|rfac2), family=gaussian, data=xdata)
  ## previously failed with "'names' attribute [3] must be the same length as the vector [1]"
  expect_is(m2, "glmmTMB")
  expect_equal(fixef(m2)$cond,
               c(`(Intercept)` = 2.09164503130437, cov = -0.0228597948394547))

})

test_that("drop dimensions in response variable", {
    ## GH #937
    mm <- transform(mtcars, mpg = scale(mpg))
    expect_is(glmmTMB(mpg ~ cyl, mm), "glmmTMB")
})

test_that("handle failure in numDeriv::jacobian",
          {
          dd <- structure(list(preMDS = c(6L, 2L, 1L, 2L, 3L, 34L, 3L, 239L, 
   1L, 2L, 4L, 81L, 1L, 1L, 1L, 255L, 8L, 72L, 110L, 3L, 6L, 61L, 
   253L, 113L, 49L, 124L, 72L, 4L, 35L, 4206L, 3660L, 3100L, 4308L, 
   5871L, 1362L, 4301L, 2673L, 204L, 216L), F_Absetzen = structure(c(1L, 
   1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 2L, 2L, 2L, 2L, 2L, 
   2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 1L, 1L, 1L, 1L, 
   1L, 1L, 1L, 1L, 1L, 1L), levels = c("0", "1"), class = "factor"), 
    Betrieb = structure(c(2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 2L, 
    2L, 2L, 2L, 3L, 3L, 5L, 8L, 8L, 8L, 8L, 8L, 8L, 8L, 8L, 8L, 
    8L, 8L, 8L, 8L, 8L, 9L, 9L, 9L, 9L, 9L, 9L, 9L, 9L, 9L, 9L
    ), levels = c("B02", "B03", "B04", "B05", "B06", "B07", "B08", 
                  "B10", "B11", "B13", "B13Zucht", "B14"), class = "factor")),
   row.names = seq(39),
   class = "data.frame")

          m1 <- suppressWarnings(
              glmmTMB(preMDS ~ 1 + F_Absetzen + (1 | Betrieb), data = dd,
                family = truncated_nbinom1))
   expect_is(m1, "glmmTMB")
})

test_that("don't mess up internal formula ordering", {
    dd <- expand.grid(type = factor(c("R","S")),
                      strainN = factor(1:3),
                      dose = c("N","C"),
                      rep = factor(1:5),
                      aid = factor(1:5),
                      rep = 1:10)
    set.seed(101)
    dd$l3 <- rnorm(nrow(dd))
    form <- l3~(type/strainN)*dose
    m1 <- glmmTMB(form, data = dd)
    expect_identical(colnames(model.matrix(m1)),
                     colnames(model.matrix(form, data = dd)))
})

test_that("subset argument", {
    fms <- update(fm1, subset = Days > 0)
    expect_false(isTRUE(all.equal(fixef(fm1), fixef(fms))))
    expect_equal(fixef(fms)$cond,
                 c(`(Intercept)` = 248.63573143019875,
                   Days = 10.904528975303338))
})

test_that("start argument is a named list", {
  expect_error(glmmTMB(mpg ~ hp, data = mtcars, start = c(0, 1)),
               "'start' should be a named list")
})

test_that("start argument has correct elements", {
  expect_error(glmmTMB(mpg ~ hp, data = mtcars, start = list(junk = 1)),
               "unrecognized vector")
})
