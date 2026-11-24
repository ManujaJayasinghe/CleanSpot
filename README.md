# CleanSpot
Our website is a Dengue Risk Monitoring Platform that allows users to report mosquito-breeding sites, earn points for valid reports, and view dengue risks through a live map and historical data.

## Maps key setup

CleanSpot reads the Google Maps API key solely from local, git-ignored configuration files (no hardcoded fallback key is committed to the repository). If the key is not configured, the Risk Map (`lib/features/map`) and Authority Dashboard map (`lib/features/authority`) display a **"Map key not set"** message instead of crashing.

### 1. Android (`android/local.properties`)
Add the following line to `android/local.properties` (git-ignored):

```properties
MAPS_API_KEY=your_google_maps_api_key_here
```

### 2. iOS (`ios/Flutter/Secrets.xcconfig`)
Create `ios/Flutter/Secrets.xcconfig` (git-ignored) and add:

```xcconfig
MAPS_API_KEY=your_google_maps_api_key_here
```

### 3. Restrict the key in Google Cloud Console
To protect your Google Maps API key in **Google Cloud Console**:

1. Open **Google Cloud Console → APIs & Services → Credentials** and select your Maps API key.
2. Under **Application restrictions**:
   - **Android apps**: Choose **Android apps**, click **Add**, and enter the package name `com.example.clean_spot` and your signing certificate's **SHA-1 fingerprint** (run `cd android && ./gradlew signingReport` to view debug/release SHA-1 fingerprints).
   - **iOS apps**: Choose **iOS apps**, click **Add**, and enter the bundle identifier `com.example.cleanSpot`.
3. Under **API restrictions**:
   - Choose **Restrict key** and select only **Maps SDK for Android** and **Maps SDK for iOS**.
4. Click **Save**.

