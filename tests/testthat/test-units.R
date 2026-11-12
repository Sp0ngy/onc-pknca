test_that("gamma counts are converted to MBq/mL", {
  # 60000 counts in 2 min = 30000 cpm; minus 30 cpm background = 29970 cpm
  # 29970 cpm / 6 cpm/Bq = 4995 Bq in 0.5 mL = 9990 Bq/mL = 0.00999 MBq/mL
  expect_equal(net_cpm(60000, 2, 30), 29970)
  expect_equal(cpm_to_bq(29970, 6), 4995)
  expect_equal(counts_to_mbq_per_ml(60000, 2, 30, 6, 0.5), 0.00999)
  # 1:10 pre-dilution
  expect_equal(counts_to_mbq_per_ml(60000, 2, 30, 6, 0.5, dilution_factor = 10), 0.0999)
  # missing dilution factor = undiluted
  expect_equal(counts_to_mbq_per_ml(60000, 2, 30, 6, 0.5, dilution_factor = NA), 0.00999)
})

test_that("aliquot weight is converted to volume with the matrix density", {
  expect_equal(aliquot_volume_ml(NA, 1.06, 1.06), 1)
  expect_equal(aliquot_volume_ml(0.2, 5, 1.06), 0.2)   # volume wins if both are given
})

test_that("PKNCA unit table converts CL to L/h, Vz to L and fe to %", {
  u <- nca_units(test_cfg())
  conv <- function(p) u$conversion_factor[u$PPTESTCD == p]
  expect_equal(u$PPSTRESU[u$PPTESTCD == "cl.obs"], "L/h")
  expect_equal(conv("cl.obs"), 1e-3)
  expect_equal(u$PPSTRESU[u$PPTESTCD == "vz.obs"], "L")
  expect_equal(conv("vz.obs"), 1e-3)
  expect_equal(u$PPSTRESU[u$PPTESTCD == "fe"], "%")
  expect_equal(conv("fe"), 100)
})
