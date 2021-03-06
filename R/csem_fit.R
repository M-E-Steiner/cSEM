#' Model-implied indicator or construct variance-covariance matrix
#'
#' Calculate the model-implied indicator or construct variance-covariance (VCV) 
#' matrix. Currently only the model-implied VCV for recursive linear models 
#' is implemented (including models containing second order constructs).
#' 
#' Notation is taken from \insertCite{Bollen1989;textual}{cSEM}.
#' If `.saturated = TRUE` the model-implied variance-covariance matrix is calculated 
#' for a saturated structural model (i.e., the VCV of the constructs is replaced 
#' by their correlation matrix). Hence: V(eta) = WSW' (possibly disattenuated).
#'
#' @usage fit(
#'   .object    = NULL, 
#'   .saturated = args_default()$.saturated,
#'   .type_vcv  = args_default()$.type_vcv
#'   )
#'
#' @inheritParams csem_arguments
#'
#' @return Either a (K x K) matrix or a (J x J) matrix depending on the `type_vcv`.
#' 
#' @references
#'   \insertAllCited{}
#'   
#' @seealso [csem()], [foreman()], [cSEMResults]
#'
#' @export

fit <- function(
  .object    = NULL, 
  .saturated = args_default()$.saturated,
  .type_vcv  = args_default()$.type_vcv
  ) {
  UseMethod("fit")
}

#' @export

fit.cSEMResults_default <- function(
  .object    = NULL, 
  .saturated = args_default()$.saturated,
  .type_vcv  = args_default()$.type_vcv
  ) {
  
  ### For maintenance: ---------------------------------------------------------
  ## Cons_exo  := (J_exo x 1) vector of exogenous constructs names.
  ## Cons_endo := (J_endo x 1) vector of endogenous constructs names.
  ## S         := (K x K) Empirical indicator VCV matrix: V(X).
  ## B         := (J_endo x J_endo) matrix of (estimated) path coefficients 
  ##              from endogenous to endogenous constructs. (zero if there is no path)
  ## Gamma     := (J_endo x J_exo) matrix of (estimated) path coefficients from
  ##              exogenous to endogenous constructs.
  ## Lambda    := (J X K) matrix of factor (dissatenuated if requested) 
  ##              and/or composite loadings.
  ## Phi       := (J_exo x J_exo) empirical construct correlation matrix 
  ##              between exogenous constructs (attenuated if requested).
  ## I         := (J_endo x J_endo) identity matrix.
  ## Theta     := (K x K) diagonal matrix of measurement model error variances.
  ## Psi       := (J_endo x J_endo) diagonal matrix of structural model error 
  ##              variances (zetas).
  ## Corr_exo_endo := (J_exo x J_endo) model-implied correlation matrix between 
  ##                  exogenous and endogenous constructs.
  ## Corr_endo     := (J_endo x J_endo)  model-implied correlation matrix between
  ##                  endogenous constructs.
  
  ### Preparation ==============================================================
  ## Check if linear
  if(.object$Information$Model$model_type != "Linear"){
    stop2(
      "The following error occured while computing the model-implied",
      " indicator correlation matrix:\n",
      "`fit()` currently not applicable to nonlinear models.")
  }
  
  mod       <- .object$Information$Model
  S         <- .object$Estimates$Indicator
  Lambda    <- .object$Estimates$Loading_estimates
  Theta     <- diag(diag(S) - diag(t(Lambda) %*% Lambda))
  dimnames(Theta) <- dimnames(S)
  
  m         <- mod$structural
  if(all(m == 0)) {.saturated <- TRUE}
  
  ### VCV of the constructs ====================================================
  if(.saturated) {
    # If a saturated model is assumed the structural model is ignored in
    # the calculation of the construct VCV (i.e. a full graph is estimated). 
    # Hence: V(eta) = WSW' (possibly disattenuated)
    vcv_construct <- .object$Estimates$Construct_VCV
    
  } else {
    Cons_endo <- mod$cons_endo
    Cons_exo  <- mod$cons_exo
    
    # ## Check if recursive, otherwise return a warning
    # if(any(m[Cons_endo, Cons_endo] + t(m[Cons_endo, Cons_endo]) == 2)){
    #   warning2(
    #     "The following warning occured while computing the model-implied",
    #     " indicator correlation matrix:\n",
    #     "Currently, `fit()` does not handle non-recursive models correctly.",
    #     " The model-implied indicator correlation matrix is likely to be wrong.")
    # }
    
    B      <- .object$Estimates$Path_estimates[Cons_endo, Cons_endo, drop = FALSE]
    Gamma  <- .object$Estimates$Path_estimates[Cons_endo, Cons_exo, drop = FALSE]
    Phi    <- .object$Estimates$Construct_VCV[Cons_exo, Cons_exo, drop = FALSE]
    I      <- diag(length(Cons_endo))
    
    ## Calculate variance of the zetas
    # Note: this is not yet fully correct, athough it does not currently affect 
    # the results. This may have to be fixed in the future to avoid potential 
    # problems that might arise in setups we have not considered yet.
    vec_zeta <- 1 - rowSums(.object$Estimates$Path_estimates * 
                              .object$Estimates$Construct_VCV)
    names(vec_zeta) <- rownames(.object$Estimates$Construct_VCV)
    
    vcv_zeta <- matrix(0, nrow = nrow(I), ncol = ncol(I))
    diag(vcv_zeta) <- vec_zeta[Cons_endo]
    
    ## Correlations between exogenous and endogenous constructs
    Corr_exo_endo <- Phi %*% t(Gamma) %*% t(solve(I-B))
    ## Correlations between endogenous constructs 
    Cor_endo <- solve(I-B) %*% (Gamma %*% Phi %*% t(Gamma) + vcv_zeta) %*% t(solve(I-B))
    diag(Cor_endo) <- 1
    
    vcv_construct <- rbind(
      cbind(Phi, Corr_exo_endo),
      cbind(t(Corr_exo_endo), Cor_endo)
      ) 
    ## Make symmetric
    vcv_construct[lower.tri(vcv_construct)] <- t(vcv_construct)[lower.tri(vcv_construct)]
    
    # Take correlation between construct error terms into account. 
    # Overwrite the values of the model-implied construct VCV with the values 
    # of the construct VCV (W'SW, corrected for attenuation) if the constructs 
    # are correlated.
    if(all(dim(mod$cor_specified)) != 0) {
      
      cc_names <- intersect(rownames(vcv_construct), rownames(mod$cor_specified))
      relevant_correlations <- mod$cor_specified[cc_names, cc_names,drop=FALSE]
      
      temp <- which(relevant_correlations == 1, arr.ind = TRUE)
      vcv_construct[cc_names, cc_names][temp] <-.object$Estimates$Construct_VCV[cc_names, cc_names][temp]
    }
  }
  
  ## If only the fitted construct VCV is needed, return it now
  if(.type_vcv == "construct") {
    return(vcv_construct)
  }
  
  ## Calculate model-implied VCV of the indicators
  vcv_ind <- t(Lambda) %*% vcv_construct %*% Lambda
  
  Sigma <- vcv_ind + Theta
  
  ## Make symmetric
  Sigma[lower.tri(Sigma)] <- t(Sigma)[lower.tri(Sigma)]
  
  ## Replace indicators connected to a composite by their correponding elements of S.
  composites <- names(mod$construct_type[mod$construct_type == "Composite"])
  index  <- t(mod$measurement[composites, , drop = FALSE]) %*% mod$measurement[composites, , drop = FALSE]

  Sigma[which(index == 1)] <- S[which(index == 1)]
  
  # Replace indicators whose measurement errors are allowed to be correlated by s_ij
  Sigma[mod$error_cor == 1] = S[mod$error_cor == 1]
  
  return(Sigma)
}

#' @export

fit.cSEMResults_multi <- function(
  .object    = NULL,
  .saturated = args_default()$.saturated,
  .type_vcv  = args_default()$.type_vcv
  ) {
  
  if(inherits(.object, "cSEMResults_2ndorder")) {
    lapply(.object, fit.cSEMResults_2ndorder, 
           .saturated = .saturated,
           .type_vcv  = .type_vcv)
  } else {
    lapply(.object, fit.cSEMResults_default, 
           .saturated = .saturated,
           .type_vcv  = .type_vcv)
  }
}

#' @export

fit.cSEMResults_2ndorder <- function(
  .object    = NULL,
  .saturated = args_default()$.saturated,
  .type_vcv  = args_default()$.type_vcv
  ) {
  
  # Which variables are second orders
  vars_2nd <- .object$Second_stage$Information$Arguments_original$.model$vars_2nd
  
  ## Get relevant quantities
  S <- .object$First_stage$Estimates$Indicator_VCV
  # Select only columns/rows that are not repeated indicators (if there are no
  # repeated indicators this will simply select all columns of S)
  selector <- !grepl("_2nd_", colnames(S))
  S <- S[selector, selector]
  
  # vcv_construct is the "indicator" vcv of the second stage. 
  vcv_construct <- fit.cSEMResults_default(.object$Second_stage, 
                                           .saturated = .saturated,
                                           .type_vcv  = 'indicator')
  
  # Select Lambda and Theta (without repeated indicator and second
  # order constructs if there are any)
  Lambda   <- .object$First_stage$Estimates$Loading_estimates
  Lambda   <- Lambda[setdiff(rownames(Lambda), vars_2nd), selector]
  Theta    <- diag(diag(S) - diag(t(Lambda) %*% Lambda))
  
  # Reorder dimnames to match the order of Lambda and ensure symmetrie
  vcv_construct <- vcv_construct[rownames(Lambda), rownames(Lambda)]
  
  ## If only the fitted construct VCV is needed, return it now
  if(.type_vcv == "construct") {
    return(vcv_construct)
  }
  
  # Compute VCV and ensure symmetrie
  Sigma <- t(Lambda) %*% vcv_construct %*% Lambda + Theta
  Sigma[lower.tri(Sigma)] <- t(Sigma)[lower.tri(Sigma)]
  
  # Replace composite blocks by corresponding elements of S
  m          <- .object$First_stage$Information$Model
  composites <- setdiff(names(m$construct_type[m$construct_type == "Composite"]), vars_2nd)
  index      <- t(m$measurement[composites, selector , drop = FALSE]) %*% m$measurement[composites, selector, drop = FALSE]
  
  Sigma[which(index == 1)] <- S[which(index == 1)]
  
  # Replace indicators whose measurement errors are allowed to be correlated by s_ij
  Sigma[m$error_cor[selector, selector] == 1] = S[m$error_cor[selector, selector] == 1]
  Sigma
  
  return(Sigma)
}
  