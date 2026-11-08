categorize_count <- function(count) {
  data.table::fcase(
    count == 0, 0L,
    count == 1, 1L,
    count >= 2, 2L,
    default = NA_integer_
  )
}