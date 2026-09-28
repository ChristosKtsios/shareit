# Οι περισσότερες βιβλιοθήκες (Firebase, Google Play Services, Google Maps,
# Flutter engine) κουβαλάνε ΤΑ ΔΙΚΑ ΤΟΥΣ consumer-rules.pro μέσα στο AAR τους
# — το Android Gradle Plugin τα συγχωνεύει αυτόματα, οπότε ΔΕΝ χρειάζεται να
# τα επαναλάβουμε εδώ. Ένα ευρύ `-keep class com.google.** { *; }` θα
# εξαιρούσε τεράστιο κομμάτι κώδικα από την obfuscation — ακριβώς αντίθετο
# από τον στόχο μας. Κρατάμε το αρχείο ελάχιστο, μόνο ό,τι είναι πραγματικά
# αναγκαίο για κώδικα που προσπελαύνεται μέσω reflection.

# Parcelable/Serializable: το R8 μπορεί να αφαιρέσει το CREATOR field ή
# constructors που χρησιμοποιούνται μόνο μέσω reflection από το Android
# framework (π.χ. κατά την ανάκτηση ενός Intent extra).
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses

# Stack traces σε Crashlytics/logcat παραμένουν χρήσιμα (line numbers) χωρίς
# να αποκαλύπτουν πραγματικά ονόματα κλάσεων.
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile
