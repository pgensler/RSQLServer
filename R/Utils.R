if(getRversion() >= "2.15.1") {
  utils::globalVariables(c("REQUIRED_JTDS_FIELDS", "OPTIONAL_JTDS_FIELDS"))
}

# jTDS FAQ
# http://jtds.sourceforge.net/faq.html
# Accessed: 8 October 2014
# General form:
# jdbc:jtds:<server_type>://<server>[:<port>][/<database>][;<property>=<value>[;...]]
# where:
# <server_type> is one of either 'sqlserver' or 'sybase' (their meaning is
#    quite obvious),
# <port> is the port the database server is listening to (default is 1433 for
#    SQL Server and 7100 for Sybase)
# <database> is the database name -- JDBC term: catalog -- (if not specified,
# the user's default database is used).
# More on FAQ about available properties.

REQUIRED_JTDS_FIELDS <- c("server")
OPTIONAL_JTDS_FIELDS <-  c("port", "database", "appName", "autoCommit",
  "batchSize", "bindAddress", "bufferDir", "bufferMaxMemory", "bufferMinPackets",
  "cacheMetaData", "charset", "domain", "instance", "lastUpdateCount",
  "lobBuffer", "loginTimeout", "macAddress", "maxStatements", "namedPipe",
  "packetSize", "password", "prepareSQL", "progName", "processId",
  "sendStringParametersAsUnicode", "socketTimeout", "socketKeepAlive",
  "ssl", "tcpNoDelay", "TDS", "useCursors", "useJCIFS", "useLOBs",
  "useNTLMv2", "user", "wsid", "xaEmulation")

jtds_url <- function (server, type = "sqlserver", port = "", database = "",
  properties = list()) {
  assertthat::assert_that(type %in% c("sqlserver", "sybase"))
  url <- paste0('jdbc:jtds:sqlserver://', server)
  if (!identical(port, ""))
    url <- paste0(url, ':', port)
  if (!identical(database, ""))
    url <- paste0(url, '/', database)
  if (!identical(properties, list())) {
    assertthat::assert_that(all(names(properties) %in% OPTIONAL_JTDS_FIELDS))
    properties <- paste0(paste0(";", names(properties)), '=',
      unlist(properties, use.names = FALSE), collapse='')
    url <- paste0(url, properties)
  }
  url
}

#' Get server details from YAML file
#'
#' The \code{sql.yaml} file in a user's \code{HOME} directory can store
#' server details and login credentials (in plaintext). This works around
#' the instability associated with jTDS's single-sign on functionality.
#' The YAML file format is documented in this package's \code{README} file, while
#' an example is provided in \code{extdata/sql.yaml} (see example). At a
#' high level, each server should be documented in its own associative array
#' with each aspect of the server documented in an associative array.
#'
#' @param server corresponds to the server name key in the YAML \code{file} and
#' should be a string.
#' @param file defaults to \code{NULL} which means that it will use
#' \code{$HOME/sql.yaml}.
#' @return a named list of \code{server} details if this is specified in the
#' \code{file}. It stops and returns an error if \code{port} and \code{type}
#' keys are not specified for found \code{server}. \code{NULL} is returned if
#' the \code{file} does not contain the \code{server} key
#' @examples
#' # See link below
#' aw <- dbConnect(RSQLServer::SQLServer(), server = "mhknbn2kdz.database.windows.net",
#'  database = 'AdventureWorks2012',
#'  properties = list(user = "sqlfamily", password = "sqlf@@m1ly"))
#' dbListTables(aw)
#' @seealso
#' \href{https://github.com/imanuelcostigan/RSQLServer/blob/master/README.md}{RSQLServer README}
#' \href{https://github.com/yaml/yaml}{YAML}
#' \href{http://sqlblog.com/blogs/jamie_thomson/archive/2012/03/27/adventureworks2012-now-available-to-all-on-sql-azure.aspx}{Example SQL Server instance}
#' @keywords internal

get_server_details <- function (server, file = NULL) {
  assertthat::assert_that(assertthat::is.string(server))
  server_details <- yaml::yaml.load_file(file)
  if (assertthat::has_name(server_details, server)) {
    server_detail <- server_details[[server]]
    assertthat::assert_that(!is.null(server_detail$port),
      !is.null(server_detail$type))
    return(server_detail)
  } else {
    return(NULL)
  }
}

#' Checks availability of TEST server
#'
#' SQL Server details can be specified in a \code{~/sql.yaml} file.
#' To be able to run examples and some tests in the package, it is necessary for
#' there to be a valid server with name TEST in this file.
#'
#' @param type specifies whether the server type is \code{"sqlserver"} (default)
#' or \code{"sybase"}
#' @return boolean \code{TRUE} if TEST server details are available. Otherwise,
#' \code{FALSE}
#' @examples
#' have_test_server()
#' @seealso \code{\link{get_server_details}} \code{\link{dbConnect,SQLServerDriver-method}}
#' @export

have_test_server <- function (type = 'sqlserver') {
  yaml_file <- file.path(Sys.getenv("HOME"), "sql.yaml")
  if (file.exists(yaml_file)) {
    server_details <- yaml::yaml.load_file(yaml_file)
    res <- assertthat::has_name(server_details, "TEST")
    return(isTRUE(res & identical(server_details[["TEST"]]$type, type)))
  } else {
    return(FALSE)
  }
}

jtds_class_path <- function () {
  file.path(system.file('java', package = 'RSQLServer'), 'jtds-1.2.8.jar')
}

pull_class_path <- function () {
  file.path(system.file('java', package = 'RSQLServer'), "MSSQLRequestPull.jar")
}

# Fetch helpers ----------------------------------------------------------

ff <- function (res, empty_vector) {
  # Where rp_* return null because for example, you have requested to fetch
  # n = 0 records, DBItest expects an empty data frame will all the right
  # column names and types. This function ensures this is the case, and
  if (rJava::is.jnull(res)) {
    rJava::.jclear()
    empty_vector
  } else {
    res
  }
}

rp_getDoubles <- function (rp, i) {
  res <- rJava::.jcall(rp, "[D", "getDoubles", i, check = FALSE)
  ff(res, double())
}

rp_getInts <- function (rp, i) {
  res <- rJava::.jcall(rp, "[I", "getInts", i, check = FALSE)
  ff(res, integer())
}
rp_getDates <- function (rp, i) {
  res <- rJava::.jcall(rp, "[Ljava/lang/String;", "getStrings", i, check = FALSE)
  ff(res, character())
}
rp_getTimestamps <- function (rp, i) {
  res <- rJava::.jcall(rp, "[Ljava/lang/String;", "getStrings", i, check = FALSE)
  ff(res, character())
}
rp_getStrings <- function (rp, i) {
  res <- rJava::.jcall(rp, "[Ljava/lang/String;", "getStrings", i, check = FALSE)
  ff(res, character())
}

fetch_rp <- function (rp, out, cts = NULL) {
  cts <- cts %||% rJava::.jcall(rp, "[I", "mapColumns")
  for (i in seq_along(cts)) {
    new_res <- switch(as.character(cts[i]),
      "1" = rp_getDoubles(rp, i),
      "2" = rp_getInts(rp, i),
      "3" = rp_getDates(rp, i),
      "4" = rp_getTimestamps(rp, i),
      rp_getStrings(rp, i))
    out[[i]] <- c(out[[i]], new_res)
  }
  out
}

rp_to_r_type_map <- function (ctypes) {
  rp_to_r <- purrr::set_names(0:5,
    c("character", "numeric", "integer", "character", "character", "logical"))
  assertthat::assert_that(all(ctypes %in% rp_to_r))
  names(rp_to_r)[match(ctypes, rp_to_r)]
}

# SQL types --------------------------------------------------------------

char_type <- function (x, con) {
  # SQL Server 2000 does not support nvarchar(max) type.
  # TEXT is being deprecated. Make sure SQL types are UNICODE variants
  # (prefixed by N).
  # https://technet.microsoft.com/en-us/library/aa258271(v=sql.80).aspx
  n <- max(nchar(as.character(x), keepNA = FALSE))
  if (n > 4000) {
    if (dbGetInfo(con)$db.version < 9) {
      n <- "4000"
    } else {
      n <- "MAX"
    }
  }
  paste0("NVARCHAR(", n, ")")
}

binary_type <- function (x, con) {
  # SQL Server 2000 does not support varbinary(max) type.
  n <- max(nchar(x, keepNA = FALSE))
  if (n > 8000) {
    if (dbGetInfo(con)$db.version < 9) {
      # https://technet.microsoft.com/en-us/library/aa225972(v=sql.80).aspx
      n <- "8000"
    } else {
      n <- "MAX"
    }
  }
  paste0("VARBINARY(", n, ")")
}

date_type <- function (x, con) {
  if (dbGetInfo(con)$db.version < 10) {
    # DATE available in >= SQL Server 2008 (>= v.10)
    "DATETIME"
  } else {
    "DATE"
  }
}
