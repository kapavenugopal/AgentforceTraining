trigger AccountTrigger on Account
  (before insert, before update) {
 
  if (Trigger.isInsert) {
    AccountHandler.beforeInsert(Trigger.new);
  } else if (Trigger.isUpdate) {
    AccountHandler.beforeUpdate(
      Trigger.new, Trigger.oldMap);
  }
}