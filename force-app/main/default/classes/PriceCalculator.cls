public class PriceCalculator {
  public static Decimal total(List<Decimal> prices) {
    Decimal sum = 0;
    for (Decimal p : prices) {
      if (p != null) { sum += p; }
    }
    if (sum > 1000) { sum = sum * 0.8; }
    system.debug('>>>>Total Sum '+ sum);
    system.debug('Final Total Sum '+ sum);
    

    return sum;
  }
  public static String run(List<Decimal> prices) {
    try { 
        return 'Total: ' + total(prices); }
    catch (Exception e) { 
        system.debug('Error: ' + e.getMessage());
        return 'Error: ' + e.getMessage(); }
    finally { System.debug('Done'); }
  }
}