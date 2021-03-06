############################
# Get the alternative design matrix
############################
.getAlternative <- function(alternative, data, n) {

  # coerce alternative into a matrix
  if (is.data.frame(alternative)) {
    if (all(sapply(alternative, is.numeric))) {
      alternative <- as.matrix(alternative)
    } else {
      stop("argument \"alternative\" could not be coerced into a matrix")
    }
  }
  if (is.vector(alternative)) {
    if (is.numeric(alternative)) {
      alternative <- as.matrix(alternative)
      colnames(alternative) <- "x"
    } else {
      stop("argument \"alternative\" could not be coerced into a matrix")
    }
  }
  # transpose if desired
  if (gt.options()$transpose && is.matrix(alternative))
    alternative <- t(alternative)
  if (is(alternative, "ExpressionSet")) {
    alternative <- t(exprs(alternative))
  }
  if (is(alternative, "formula")) {

    # keep NAs
    old.na.action <- options()$na.action  
    options(na.action="na.pass")

    # make appropriate contrasts
    mframe <- model.frame(alternative, data=data)
    factors <- names(mframe)[sapply(mframe, is.factor)]
    contrs <- lapply(factors, function(fac) {
      levs <- levels(mframe[[fac]])
      k <- length(levs)
      if (is.ordered(mframe[[fac]])) {
        contr <- matrix(0,k,k)
        contr[lower.tri(contr,diag=TRUE)] <- 1
      } else {
        contr <- diag(k)
      }
      rownames(contr) <- colnames(contr) <- levs                     
      contr 
    })
    names(contrs) <- factors
                             
    # make the design matrix
    alternative <- terms(alternative, data=data)
    if (length(attr(alternative, "term.labels")) == 0)
      stop("empty alternative")
    attr(alternative, "intercept") <- 1
    alternative <- model.matrix(alternative, contrasts.arg=contrs, data=data)
    alternative <- alternative[,colnames(alternative) != "(Intercept)",drop=FALSE]    # ugly, but I've found no other way
    
    # restore default
    options(na.action = old.na.action)
  }

  #check dimensions and names
  if (nrow(alternative) != n) {
    stop("the length of \"response\" (",n, ") does not match the row count of \"alternative\" (", nrow(alternative), ")")
  }
  if (is.null(colnames(alternative)))
    stop("colnames missing in alternative design matrix")

  alternative
}

############################
# Get the null design matrix
############################
.getNull <- function(null, data, n, model) {

  # coerce null into a matrix and find the offset term
  offset <- NULL
  if (is.data.frame(null) || is.vector(null)) {
    if (all(sapply(null, is.numeric))) {
      null <- as.matrix(null)
    } else {
      stop("argument \"null\" could not be coerced into a matrix")
    }
  }
  if (is(null, "formula")) {
    if (is.null(data)) {
      tnull <- terms(null)
      # prevent problems for input ~1 or ~0:
      if ((attr(tnull, "response") == 0) && (length(attr(tnull, "term.labels")) == 0)
          && (length(attr(tnull, "offset")) == 0)) {
        if (attr(tnull, "intercept") == 1)
          tnull <- terms(numeric(n) ~ 1)
        else
          tnull <- terms(numeric(n) ~ 0)
      }
      offset <- model.offset(model.frame(tnull))
    } else {
      offset <- model.offset(model.frame(null, data=data))
      tnull <- terms(null, data=data)
    }
    data <- model.frame(tnull, data, drop.unused.levels = TRUE)
    null <- model.matrix(tnull, data)
 
    # suppress intercept if necessary (can this be done more elegantly?)
    if (model == "cox") null <- null[,colnames(null) != "(Intercept)",drop=FALSE]
  }

  # check dimensions
  if (nrow(null) != n) {
    stop("the length of \"response\" (",n, ") does not match the row count of \"null\" (", nrow(null), ")")
  }

  list(null = null, offset = offset)
}


############################
# Iterative function calculates all permutations of a vector
# values: vector of all unique values
# multiplicity: multiplicity of each value
############################
.allpermutations <- function(values, multiplicity) {

  if (length(values)==1) {
    out <- values
  } else {
    n <- sum(multiplicity)
    out <- matrix(0 , n, .npermutations(multiplicity))
    where <- 0
    for (i in 1:length(values)) {
      if (multiplicity[i] == 1) {
        newmult <- multiplicity[-i]
        newvals <- values[-i]
      } else {
        newmult <- multiplicity
        newmult[i] <- newmult[i] - 1
        newvals <- values
      }
      range <- where + seq_len(.npermutations(newmult))
      where <- range[length(range)]
      out[1,range] <- values[i]
      out[2:n, range] <- .allpermutations(newvals, newmult)
    }
  }
  out
}

############################
# Iterative function counts all permutations of a vector
# values: vector of all unique values
# multiplicity: multiplicity of each value
############################
.npermutations <- function(multiplicity) {
  round(exp(lfactorial(sum(multiplicity)) - sum(lfactorial(multiplicity))))
}

############################
# Counts all permutations of a vector y
# user-friendly version of .npermutations()
############################
npermutations <- function(y) {
  .npermutations(table(y))
}

############################
# Calculates all permutations of a vector y
# user-friendly version of .allpermutations()
############################
allpermutations <- function(y) {
  values <- unique(y)
  multiplicity <- colSums(outer(y, values, "=="))
  .allpermutations(values, multiplicity)
}


############################
# Makes the right formula
############################
.makeFormula <- function(has.null, has.offset) {
  form <- "response ~ 0"
  if (has.null) form <- paste(form, "+Z")
  if (has.offset) form <- paste(form, "+offset(offset)")
  form
}