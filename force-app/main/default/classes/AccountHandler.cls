public with sharing class AccountHandler {
  public static void beforeInsert(List<Account> recs) {
    for (Account a : recs) {
      if (a.Industry == null) { a.Industry = 'Other'; }
    }
  }
  public static void beforeUpdate(List<Account> recs,
      Map<Id, Account> oldMap) {
    // compare with oldMap.get(a.Id) here
  }
}