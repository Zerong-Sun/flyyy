/** Realized merchandise margin less travel paid, including refunds and losses. */
export function travelCharge(state, amount) {
  return { cash: state.cash - amount, profit: state.profit - amount, travelExpenses: state.travelExpenses + amount };
}
export function saleCredit(state, revenue, cost) {
  const margin = revenue - cost;
  return { cash: state.cash + revenue, profit: state.profit + margin, profitable: state.profitable + (margin > 0 && state.profit + margin > 0 ? 1 : 0) };
}

/** Cash refunds and this accounting epoch can differ for migrated tickets. */
export function refundTravel(state, rate) {
  const paid = state.ticket?.totalPaid || 0;
  const refund = Math.floor(paid * rate * 100 + 1e-8) / 100;
  const ledgerRefund = Math.min(state.travelExpenses, Math.floor((state.ticket?.ledgerPaid || 0) * rate * 100 + 1e-8) / 100);
  return { cash: state.cash + refund, profit: state.profit + ledgerRefund, travelExpenses: state.travelExpenses - ledgerRefund };
}
