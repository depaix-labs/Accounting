// Acquisition postings and October depreciation.
entry {
    id = 9960
    date = 2026-10-01
    sort regular
    details { Synthetic workstation acquisition, with input VAT. }
    for (demo_assets#workstation) in (BMvaMeiAkpIna) { debit = 1440.00 }
    for (demo_assets#workstation) in (BSchBepBtwVoo) { debit = 302.40 }
    for (audit_bank) in (BLimBanRba) { credit = 1742.40 }
    transactions { ref 7960 }
}

entry {
    id = 9961
    date = 2026-10-20
    sort regular
    details { Synthetic used display acquisition, no input VAT. }
    for (demo_assets#monitor) in (BMvaMeiAkpIna) { debit = 600.00 }
    for (audit_bank) in (BLimBanRba) { credit = 600.00 }
    transactions { ref 7961 }
}

entry {
    id = 9962
    date = 2026-10-31
    sort regular
    details { October workstation depreciation. }
    for (demo_assets#workstation) in (WAfsAmvMei) { debit = 24.00 }
    for (demo_assets#workstation) in (BMvaMeiCaeAfs) { credit = 24.00 }
}
