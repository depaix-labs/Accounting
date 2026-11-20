// Fictional assets for compiler integration coverage.
entity {
    use alias demo_assets

    unit workstation {
        details { Synthetic workstation commissioned in October 2026. }
        profile {
            acquisition {
                date { year = 2026 month = 10 day = 1 }
                entry = 9960
                account = BMvaMeiAkpIna
                valuation { acquisition_cost { direct = 1440.00 indirect = 0.00 } }
            }
            commission_date { year = 2026 month = 10 day = 1 }
        }
        depreciation {
            method = sl
            useful_life_years = 4
            residual_percent = 20
            account = WAfsAmvMei
            contra = BMvaMeiCaeAfs
        }
    }

    unit monitor {
        details { Synthetic display purchased in October and commissioned in November. }
        profile {
            acquisition {
                date { year = 2026 month = 10 day = 20 }
                entry = 9961
                account = BMvaMeiAkpIna
                valuation { acquisition_cost { direct = 600.00 indirect = 0.00 } }
            }
            commission_date { year = 2026 month = 11 day = 1 }
        }
        depreciation {
            method = sl
            useful_life_years = 5
            residual_percent = 0
            account = WAfsAmvMei
            contra = BMvaMeiCaeAfs
        }
    }
}
