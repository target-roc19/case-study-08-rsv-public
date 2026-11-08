calc_age_months <- function(anchor_date, birth_date) {
    anchor_date <- as.Date(anchor_date)
    birth_date <- as.Date(birth_date)

    age_in_months <- rep(NA_integer_, length(anchor_date))
    valid_rows <- !is.na(anchor_date) & !is.na(birth_date)

    if (!any(valid_rows)) {
        return(age_in_months)
    }

    anchor_lt <- as.POSIXlt(anchor_date[valid_rows])
    birth_lt <- as.POSIXlt(birth_date[valid_rows])

    age_in_months[valid_rows] <-
        (anchor_lt$year - birth_lt$year) * 12L +
        (anchor_lt$mon - birth_lt$mon) -
        as.integer(anchor_lt$mday < birth_lt$mday)

    age_in_months
}