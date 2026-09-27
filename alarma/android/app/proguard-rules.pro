# R8 sterge in build-ul de release informatia de tip generic pe care Gson o
# foloseste in flutter_local_notifications. Rezultatul era o exceptie la
# fiecare notificationsPlugin.cancel():
#   java.lang.RuntimeException: Missing type parameter
#     at FlutterLocalNotificationsPlugin.loadScheduledNotifications
# Exceptia oprea tot codul de dupa apel — inclusiv programarea snooze-ului.
# Bug vizibil DOAR in release; in debug nu ruleaza R8, de aceea testele pe
# emulator (build debug) treceau.

-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Gson: pastreaza semnaturile generice si clasele de tip token.
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
