test_that("config converts the Lu-177 half-life to hours", {
  cfg <- test_cfg()
  expect_equal(cfg$nuclide$half_life_h, 6.647 * 24)
})

test_that("decay correction: one half-life doubles, two half-lives quadruple", {
  hl <- 159.528
  expect_equal(decay_correct(50, t_measured = hl, t_reference = 0, half_life_h = hl), 100)
  expect_equal(decay_correct(25, t_measured = 2 * hl, t_reference = 0, half_life_h = hl), 100)
  # forward in time = physical decay
  expect_equal(decay_correct(100, t_measured = 0, t_reference = hl, half_life_h = hl), 50)
  # no time difference = no change
  expect_equal(decay_correct(42, 10, 10, hl), 42)
})

test_that("decay correction works on date-times (UTC, across a DST change in Europe)", {
  hl <- 6.647 * 24
  t_inj <- parse_datetime("2026-03-28 10:00:00")
  t_meas <- parse_datetime("2026-03-29 10:00:00")       # DST switch night in Europe; UTC = exactly 24 h
  expect_equal(hours_between(t_inj, t_meas), 24)
  expect_equal(decay_correct(1, t_meas, t_inj, hl), exp(log(2) / hl * 24))
})

test_that("net injected activity corrects syringe readings to injection time", {
  hl <- 100
  t_inj <- parse_datetime("2026-01-01 10:00:00")
  # pre measured 1 half-life (100 h) before injection: 2000 MBq then -> 1000 MBq at injection
  # residual measured 1 half-life after injection: 25 MBq then -> 50 MBq at injection
  a <- net_injected_activity(
    pre_mbq = 2000, pre_time = t_inj - 100 * 3600,
    residual_mbq = 25, residual_time = t_inj + 100 * 3600,
    injection_time = t_inj, half_life_h = hl
  )
  expect_equal(a, 950)
  # missing residual counts as 0
  expect_equal(net_injected_activity(1000, t_inj, NA, as.POSIXct(NA), t_inj, hl), 1000)
})
