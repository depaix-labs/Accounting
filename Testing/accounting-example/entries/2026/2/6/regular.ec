// Fictional mock entry: office supplies paid in full, no VAT (intentionally excluded from VAT fixtures).
entry {
    id = 9951
    date = 2026-06-01
    sort regular
    for (audit_expense) in (WBedAlkOal) { debit = 50.00 }
    for (audit_bank) in (BLimBanRba) { credit = 50.00 }
}
