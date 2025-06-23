package gama.extension.GTFSfilter;

import GamaGTFSUtils.OSMUtils;
import org.locationtech.jts.geom.Envelope;
import org.onebusaway.gtfs.impl.GtfsRelationalDaoImpl;
import org.onebusaway.gtfs.serialization.GtfsReader;
import org.onebusaway.gtfs.serialization.GtfsWriter;

import com.opencsv.CSVReader;
import com.opencsv.CSVParserBuilder;
import com.opencsv.CSVReaderBuilder;
import com.opencsv.exceptions.CsvValidationException;

import java.io.*;
import java.nio.file.Files;
import java.util.*;

public class GTFSFilter {

    // Fichiers obligatoires
    private static final Set<String> REQUIRED_FILES = Set.of(
        "stops.txt", "trips.txt", "routes.txt", "stop_times.txt", "agency.txt"
    );
    // Fichiers optionnels (shapes.txt géré séparément)
            // Fichiers optionnels (calendar) — shapes.txt géré séparément
    private static final Set<String> OPTIONAL_FILES = Set.of(
        "calendar.txt",
        "calendar_dates.txt"
       
    );

    public static void filter(String gtfsDirPath, String osmFilePath, String outputDirPath) throws Exception {
        System.out.println("🔄 Début du filtrage GTFS...");
        
        Envelope env = OSMUtils.extractEnvelope(osmFilePath);
        System.out.println("✅ Enveloppe OSM extraite: " + env.toString());

        File gtfsDir = new File(gtfsDirPath);
        if (!gtfsDir.isDirectory()) {
            throw new IllegalArgumentException("Répertoire GTFS invalide: " + gtfsDirPath);
        }
        
        File outDir = new File(outputDirPath);
        if (!outDir.exists()) {
            outDir.mkdirs();
            System.out.println("📁 Répertoire de sortie créé: " + outputDirPath);
        }

        // Vérification des fichiers GTFS requis
        List<String> missingFiles = new ArrayList<>();
        for (String requiredFile : REQUIRED_FILES) {
            if (!requiredFile.equals("agency.txt")) { // agency.txt peut être généré
                File file = new File(gtfsDir, requiredFile);
                if (!file.exists()) {
                    missingFiles.add(requiredFile);
                }
            }
        }
        if (!missingFiles.isEmpty()) {
            throw new IllegalArgumentException("Fichiers GTFS manquants: " + String.join(", ", missingFiles));
        }
        System.out.println("✅ Fichiers GTFS requis vérifiés");

        // --- agency.txt ---
        handleAgencyFile(gtfsDir, outDir, osmFilePath);

        // --- stops.txt ---
        Set<String> keptStopIds = new HashSet<>();
        System.out.println("🔄 Filtrage des arrêts (stops.txt)...");
        filterAndWriteFile("stops.txt", gtfsDir, outDir, (header, row) -> {
            int idxLat = header.getOrDefault("stop_lat", -1);
            int idxLon = header.getOrDefault("stop_lon", -1);
            int idxStopId = header.getOrDefault("stop_id", -1);
            if (row.length <= Math.max(idxLat, idxLon) || idxLat < 0 || idxLon < 0 || idxStopId < 0) return false;
            try {
                double lat = Double.parseDouble(row[idxLat]);
                double lon = Double.parseDouble(row[idxLon]);
                if (env.contains(lon, lat)) {
                    keptStopIds.add(row[idxStopId]);
                    return true;
                }
            } catch (Exception e) {
                System.err.println("⚠️ Erreur parsing coordonnées pour stop: " + Arrays.toString(row));
            }
            return false;
        });
        System.out.println("✅ " + keptStopIds.size() + " arrêts conservés");

        // --- stop_times.txt ---
        Set<String> keptTripIds = new HashSet<>();
        System.out.println("🔄 Filtrage des horaires (stop_times.txt)...");
        filterAndWriteFile("stop_times.txt", gtfsDir, outDir, (header, row) -> {
            int idxStopId = header.getOrDefault("stop_id", -1);
            int idxTripId = header.getOrDefault("trip_id", -1);
            if (row.length <= Math.max(idxStopId, idxTripId) || idxStopId < 0 || idxTripId < 0) return false;
            if (keptStopIds.contains(row[idxStopId])) {
                keptTripIds.add(row[idxTripId]);
                return true;
            }
            return false;
        });
        System.out.println("✅ " + keptTripIds.size() + " voyages conservés");

        // --- trips.txt ---
        Set<String> routesToKeep = new HashSet<>();
        Set<String> shapesToKeep = new HashSet<>();
        System.out.println("🔄 Filtrage des voyages (trips.txt)...");
        filterAndWriteFile("trips.txt", gtfsDir, outDir, (header, row) -> {
            int idxTripId = header.getOrDefault("trip_id", -1);
            int idxRouteId = header.getOrDefault("route_id", -1);
            int idxShapeId = header.getOrDefault("shape_id", -1);
            if (row.length <= Math.max(idxTripId, Math.max(idxRouteId, idxShapeId))) return false;
            String tripId = row[idxTripId];
            if (keptTripIds.contains(tripId)) {
                routesToKeep.add(row[idxRouteId]);
                if (idxShapeId >= 0) {
                    shapesToKeep.add(row[idxShapeId]);
                }
                return true;
            }
            return false;
        });
        System.out.println("✅ " + routesToKeep.size() + " routes conservées");

        // --- routes.txt ---
        System.out.println("🔄 Filtrage des routes (routes.txt)...");
        filterAndWriteFile("routes.txt", gtfsDir, outDir, (header, row) -> {
            int idxRouteId = header.getOrDefault("route_id", -1);
            if (row.length <= idxRouteId || idxRouteId < 0) return false;
            return routesToKeep.contains(row[idxRouteId]);
        });

     // --- shapes.txt (filtrage spatial des points) ---
        File shapesFile = new File(gtfsDir, "shapes.txt");
        if (shapesFile.exists()) {
            System.out.println("🔄 Filtrage spatial des points de shape (shapes.txt)…");
            filterAndWriteFile("shapes.txt", gtfsDir, outDir, (header, row) -> {
                int idxId  = header.getOrDefault("shape_id",     -1);
                int idxLat = header.getOrDefault("shape_pt_lat", -1);
                int idxLon = header.getOrDefault("shape_pt_lon", -1);
                if (idxId < 0 || idxLat < 0 || idxLon < 0) return false;
                String shapeId = row[idxId];
                // ne traiter que les shapes déjà référencés par un voyage filtré
                if (!shapesToKeep.contains(shapeId)) return false;
                try {
                  double lat = Double.parseDouble(row[idxLat]);
                  double lon = Double.parseDouble(row[idxLon]);
                  // conserver uniquement les points à l’intérieur de l’enveloppe OSM
                  return env.contains(lon, lat);
                } catch (NumberFormatException e) {
                  return false;
                }
            });
            System.out.println("✅ Points de shapes filtrés selon l’enveloppe");
        } else {
            System.out.println("ℹ️ Aucun shapes.txt trouvé, skip filtrage spatial");
        }



        // --- fichiers optionnels ---
        System.out.println("🔄 Copie des fichiers optionnels...");
        int optionalFilesCopied = 0;
        for (String filename : OPTIONAL_FILES) {
            File src = new File(gtfsDir, filename);
            if (src.exists()) {
                Files.copy(src.toPath(), new File(outDir, filename).toPath(),
                          java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                optionalFilesCopied++;
                System.out.println("✅ " + filename + " copié");
            }
        }
        System.out.println("✅ " + optionalFilesCopied + " fichiers optionnels copiés");

        // --- Suppression fichiers non listés ---
        cleanupUnwantedFiles(outDir);

        // Nettoyage et validation
        System.out.println("🔄 Nettoyage des données...");
        pruneAllFiles(outDir);
        
        String cleanedDir = outputDirPath + "_cleaned";
        System.out.println("🔄 Nettoyage avec OneBusAway...");
        cleanWithOneBusAway(outputDirPath, cleanedDir);
        
        System.out.println("🔄 Validation avec GTFS-Validator...");
        ValidationResult result = validateWithGtfsValidator(cleanedDir);
        
        if (result.hasErrors()) {
            System.err.println("⚠️ GTFS-Validator a détecté " + result.getErrorCount() + " erreur(s)");
            System.err.println("📁 Voir détails dans: " + result.getValidationPath());
            if (result.hasCriticalErrors()) {
                System.err.println("❌ Erreurs critiques détectées - les données peuvent être inutilisables");
            } else {
                System.out.println("💡 Erreurs mineures seulement - les données restent utilisables");
            }
        } else {
            System.out.println("✅ Validation GTFS réussie - aucune erreur détectée");
        }
        
        System.out.println("✅ Filtrage GTFS terminé avec succès!");
        System.out.println("📁 Résultats dans: " + cleanedDir);
    }


    private static void handleAgencyFile(File gtfsDir, File outDir, String osmFilePath) throws IOException {
        File agencySrc = new File(gtfsDir, "agency.txt");
        File agencyDest = new File(outDir, "agency.txt");

        if (agencySrc.exists() && agencySrc.length() > 0) {
            // Vérification basique du contenu
            try (BufferedReader reader = new BufferedReader(new FileReader(agencySrc))) {
                String header = reader.readLine();
                String firstLine = reader.readLine();
                if (header != null && firstLine != null && !firstLine.trim().isEmpty()) {
                    Files.copy(agencySrc.toPath(), agencyDest.toPath(), 
                              java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                    System.out.println("✅ agency.txt copié depuis la source");
                    return;
                }
            } catch (Exception e) {
                System.err.println("⚠️ Erreur lecture agency.txt source: " + e.getMessage());
            }
        }

        // Génération d'un fichier agency.txt adaptatif
        generateDefaultAgencyFile(agencyDest, osmFilePath);
    }

    private static void generateDefaultAgencyFile(File agencyDest, String osmFilePath) throws IOException {
        String cityName = "Default City";
        String agencyName = "Default Agency";
        String agencyUrl = "http://www.example.com";
        String agencyTimezone = "UTC";

        // Tentative d'extraction du nom de ville depuis OSM (si méthode disponible)
        try {
            // cityName = OSMUtils.extractCityName(osmFilePath);
            // agencyTimezone = OSMUtils.extractTimezone(osmFilePath);
        } catch (Exception e) {
            System.out.println("💡 Utilisation des valeurs par défaut pour agency.txt");
        }

        // Variables d'environnement
        String envAgencyName = System.getenv("GTFS_AGENCY_NAME");
        String envAgencyUrl = System.getenv("GTFS_AGENCY_URL");
        String envAgencyTimezone = System.getenv("GTFS_AGENCY_TIMEZONE");
        if (envAgencyName != null) agencyName = envAgencyName;
        if (envAgencyUrl != null) agencyUrl = envAgencyUrl;
        if (envAgencyTimezone != null) agencyTimezone = envAgencyTimezone;

        try (BufferedWriter writer = new BufferedWriter(new FileWriter(agencyDest))) {
            writer.write("agency_id,agency_name,agency_url,agency_timezone\n");
            writer.write(String.format("1,%s,%s,%s\n", agencyName, agencyUrl, agencyTimezone));
            System.out.println("✅ Fichier agency.txt adaptatif généré pour: " + cityName);
        }
    }

    private static void cleanupUnwantedFiles(File outDir) {
        int removedFiles = 0;
        for (File f : Objects.requireNonNull(outDir.listFiles())) {
            String name = f.getName();
            // on ne supprime pas shapes.txt, même si ce n'est ni REQUIRED ni OPTIONAL
            if (!f.isFile() || !name.endsWith(".txt") || "shapes.txt".equals(name)) {
                continue;
            }
            if (!REQUIRED_FILES.contains(name) && !OPTIONAL_FILES.contains(name)) {
                if (f.delete()) {
                    removedFiles++;
                    System.out.println("🗑️ Fichier supprimé: " + name);
                }
            }
        }
        if (removedFiles > 0) {
            System.out.println("✅ " + removedFiles + " fichier(s) non standard(s) supprimé(s)");
        }
    }

    /**
     * Nettoie un GTFS en utilisant OneBusAway pour supprimer les données inutiles.
     */
    public static void cleanWithOneBusAway(String filteredInput, String outputDir) throws Exception {
        // Vérification préalable d'agency.txt
        File agencyFile = new File(filteredInput, "agency.txt");
        if (!agencyFile.exists() || agencyFile.length() == 0) {
            throw new IllegalStateException("Fichier agency.txt valide requis pour le traitement GTFS");
        }

        try {
            GtfsReader reader = new GtfsReader();
            reader.setInputLocation(new File(filteredInput));
            GtfsRelationalDaoImpl dao = new GtfsRelationalDaoImpl();
            reader.setEntityStore(dao);
            reader.run();

            // Création du répertoire de sortie
            File outputDirFile = new File(outputDir);
            if (!outputDirFile.exists()) {
                outputDirFile.mkdirs();
            }

            GtfsWriter writer = new GtfsWriter();
            writer.setOutputLocation(outputDirFile);
            writer.run(dao);
            writer.close();
            
            System.out.println("✅ OneBusAway : GTFS nettoyé -> " + outputDir);
            
            // Vérification des fichiers générés
            verifyCleanedOutput(outputDirFile);
            
        } catch (Exception e) {
            System.err.println("❌ Erreur OneBusAway: " + e.getMessage());
            e.printStackTrace();
            throw new Exception("Échec du nettoyage OneBusAway: " + e.getMessage(), e);
        }
    }

    private static void verifyCleanedOutput(File outputDir) {
        int fileCount = 0;
        for (String requiredFile : REQUIRED_FILES) {
            File file = new File(outputDir, requiredFile);
            if (file.exists() && file.length() > 0) {
                fileCount++;
                System.out.println("✅ " + requiredFile + " généré (" + file.length() + " bytes)");
            } else {
                System.err.println("⚠️ " + requiredFile + " manquant ou vide après nettoyage");
            }
        }
        System.out.println("📊 " + fileCount + "/" + REQUIRED_FILES.size() + " fichiers requis générés");
    }
    
    public static void pruneAllFiles(File outDir) throws Exception {
        System.out.println("🔄 Nettoyage des références croisées...");
        
        Set<String> stopIds = readIdsFromFile(new File(outDir, "stops.txt"), "stop_id");
        Set<String> tripIds = readIdsFromFile(new File(outDir, "trips.txt"), "trip_id");
        Set<String> routeIds = readIdsFromFile(new File(outDir, "routes.txt"), "route_id");

        System.out.println("📊 IDs collectés - Stops: " + stopIds.size() + 
                          ", Trips: " + tripIds.size() + ", Routes: " + routeIds.size());

        pruneFile(new File(outDir, "stop_times.txt"), "trip_id", tripIds);
        pruneFile(new File(outDir, "trips.txt"), "trip_id", tripIds);
        pruneFile(new File(outDir, "stops.txt"), "stop_id", stopIds);
        pruneFile(new File(outDir, "routes.txt"), "route_id", routeIds);
        
        System.out.println("✅ Nettoyage des références terminé");
    }

    private static Set<String> readIdsFromFile(File file, String colName) throws Exception {
        Set<String> ids = new HashSet<>();
        if (!file.exists()) {
            System.err.println("⚠️ Fichier introuvable: " + file.getName());
            return ids;
        }
        
        char sep = detectSeparator(file);
        try (CSVReader reader = new CSVReaderBuilder(new FileReader(file))
                .withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build()) {
            String[] header = reader.readNext();
            if (header == null) return ids;
            
            int idx = -1;
            for (int i = 0; i < header.length; i++) {
                if (header[i].trim().equalsIgnoreCase(colName)) { 
                    idx = i; 
                    break; 
                }
            }
            if (idx < 0) {
                System.err.println("⚠️ Colonne '" + colName + "' introuvable dans " + file.getName());
                return ids;
            }
            
            String[] line;
            while ((line = reader.readNext()) != null) {
                if (line.length > idx && !line[idx].trim().isEmpty()) {
                    ids.add(line[idx].trim());
                }
            }
        }
        return ids;
    }

    private static void pruneFile(File file, String keyCol, Set<String> keepIds) throws Exception {
        if (!file.exists()) return;
        
        File temp = new File(file.getAbsolutePath() + ".tmp");
        char sep = detectSeparator(file);
        int keptRows = 0;
        int totalRows = 0;
        
        try (
            CSVReader reader = new CSVReaderBuilder(new FileReader(file))
                .withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build();
            BufferedWriter writer = Files.newBufferedWriter(temp.toPath())
        ) {
            String[] header = reader.readNext();
            if (header == null) return;
            writer.write(String.join(String.valueOf(sep), header)); 
            writer.newLine();
            
            int idx = -1;
            for (int i = 0; i < header.length; i++) {
                if (header[i].trim().equalsIgnoreCase(keyCol)) { 
                    idx = i; 
                    break; 
                }
            }
            if (idx < 0) {
                System.err.println("⚠️ Colonne '" + keyCol + "' introuvable dans " + file.getName());
                return;
            }
            
            String[] row;
            while ((row = reader.readNext()) != null) {
                totalRows++;
                if (row.length > idx && keepIds.contains(row[idx].trim())) {
                    writer.write(String.join(String.valueOf(sep), row));
                    writer.newLine();
                    keptRows++;
                }
            }
        }
        
        Files.move(temp.toPath(), file.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        System.out.println("✅ " + file.getName() + " nettoyé: " + keptRows + "/" + totalRows + " lignes conservées");
    }

    private static char detectSeparator(File file) throws IOException {
        try (BufferedReader r = new BufferedReader(new FileReader(file))) {
            String line = r.readLine();
            if (line == null) return ',';
            if (line.contains(";")) return ';';
            if (line.contains("\t")) return '\t';
            return ',';
        }
    }

    private static void filterAndWriteFile(String filename, File inDir, File outDir, RowPredicate keepRow) 
            throws IOException, CsvValidationException {
        File inFile = new File(inDir, filename);
        if (!inFile.exists()) {
            System.err.println("⚠️ Fichier source manquant: " + filename);
            return;
        }
        
        char sep = detectSeparator(inFile);
        int totalRows = 0;
        int keptRows = 0;
        
        try (
            Reader reader = new BufferedReader(new FileReader(inFile));
            CSVReader csvReader = new CSVReaderBuilder(reader)
                .withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build();
            BufferedWriter writer = Files.newBufferedWriter(new File(outDir, filename).toPath())
        ) {
            String[] header = csvReader.readNext();
            if (header == null) return;
            writer.write(String.join(String.valueOf(sep), header)); 
            writer.newLine();
            
            Map<String, Integer> headerIdx = new HashMap<>();
            for (int i = 0; i < header.length; i++) 
                headerIdx.put(header[i].trim().toLowerCase(), i);
            
            String[] row;
            while ((row = csvReader.readNext()) != null) {
                if (row.length == 0) continue;
                totalRows++;
                if (keepRow.keep(headerIdx, row)) {
                    writer.write(String.join(String.valueOf(sep), row));
                    writer.newLine();
                    keptRows++;
                }
            }
        }
        System.out.println("✅ " + filename + ": " + keptRows + "/" + totalRows + " lignes conservées");
    }

    public static ValidationResult validateWithGtfsValidator(String outputDirPath) throws Exception {
        File filteredDir = new File(outputDirPath);
        
        // Recherche du fichier JAR du validateur
        File projectRoot = filteredDir.getAbsoluteFile();
        while (projectRoot != null && !(new File(projectRoot, "lib").exists())) {
            projectRoot = projectRoot.getParentFile();
        }
        
        if (projectRoot == null) {
            throw new RuntimeException("Impossible de localiser le dossier 'lib' depuis : " + outputDirPath);
        }
        
        String validatorJar = new File(projectRoot, "lib/gtfs-validator-7.1.0-cli.jar").getAbsolutePath();
        File jarFile = new File(validatorJar);
        if (!jarFile.exists()) {
            throw new RuntimeException("Fichier gtfs-validator-7.1.0-cli.jar introuvable à : " + 
                                     jarFile.getAbsolutePath());
        }
        
        String validationOut = outputDirPath + File.separator + "validation";
        File validationDir = new File(validationOut);
        if (!validationDir.exists()) {
            validationDir.mkdirs();
        }
        
        // Construction de la commande
        List<String> command = new ArrayList<>();
        command.add("java");
        command.add("-jar");
        command.add(validatorJar);
        command.add("--input");
        command.add(outputDirPath);
        // Optionnel: spécifier le dossier de sortie selon votre version
        // command.add("--output");
        // command.add(validationOut);
        
        ProcessBuilder pb = new ProcessBuilder(command);
        pb.directory(new File(outputDirPath).getParentFile());
        
        // Capture des sorties
        ByteArrayOutputStream stdout = new ByteArrayOutputStream();
        ByteArrayOutputStream stderr = new ByteArrayOutputStream();
        
        try {
            Process proc = pb.start();
            
            // Redirection des flux
            Thread stdoutThread = new Thread(() -> {
                try (InputStream is = proc.getInputStream()) {
                    is.transferTo(stdout);
                } catch (IOException e) {
                    // Ignore
                }
            });
            
            Thread stderrThread = new Thread(() -> {
                try (InputStream is = proc.getErrorStream()) {
                    is.transferTo(stderr);
                } catch (IOException e) {
                    // Ignore
                }
            });
            
            stdoutThread.start();
            stderrThread.start();
            
            int code = proc.waitFor();
            stdoutThread.join(5000);
            stderrThread.join(5000);
            
            String stdoutStr = stdout.toString();
            String stderrStr = stderr.toString();
            
            System.out.println("📊 GTFS-Validator terminé avec code: " + code);
            if (!stdoutStr.isEmpty()) {
                System.out.println("📝 Sortie standard: " + stdoutStr);
            }
            if (!stderrStr.isEmpty()) {
                System.err.println("⚠️ Erreurs/Avertissements: " + stderrStr);
            }
            
            // Analyse des résultats
            return analyzeValidationResults(validationDir, code, stdoutStr, stderrStr);
            
        } catch (Exception e) {
            throw new RuntimeException("Erreur lors de l'exécution du GTFS-Validator: " + e.getMessage(), e);
        }
    }
    
    private static ValidationResult analyzeValidationResults(File validationDir, int exitCode, 
                                                           String stdout, String stderr) {
        ValidationResult result = new ValidationResult(validationDir.getAbsolutePath(), exitCode);
        
        // Recherche des fichiers de rapport
        File[] reportFiles = validationDir.listFiles((dir, name) -> 
            name.endsWith(".json") || name.endsWith(".html") || name.endsWith(".txt"));
        
        if (reportFiles != null) {
            for (File reportFile : reportFiles) {
                result.addReportFile(reportFile.getAbsolutePath());
                System.out.println("📋 Rapport trouvé: " + reportFile.getName());
            }
        }
        
        // Analyse basique du contenu pour déterminer la sévérité
        if (exitCode != 0) {
            result.setHasErrors(true);
            
            // Détection d'erreurs critiques vs avertissements
            String combined = (stdout + " " + stderr).toLowerCase();
            if (combined.contains("error") || combined.contains("invalid") || combined.contains("missing")) {
                if (combined.contains("fatal") || combined.contains("critical")) {
                    result.setCriticalErrors(true);
                }
            }
        }
        
        return result;
    }

    @FunctionalInterface
    interface RowPredicate {
        boolean keep(Map<String, Integer> header, String[] row);
    }
    
    // Classe pour encapsuler les résultats de validation
    public static class ValidationResult {
        private String validationPath;
        private int exitCode;
        private boolean hasErrors = false;
        private boolean criticalErrors = false;
        private List<String> reportFiles = new ArrayList<>();
        private int errorCount = 0;
        
        public ValidationResult(String validationPath, int exitCode) {
            this.validationPath = validationPath;
            this.exitCode = exitCode;
        }
        
        public String getValidationPath() { return validationPath; }
        public int getExitCode() { return exitCode; }
        public boolean hasErrors() { return hasErrors; }
        public boolean hasCriticalErrors() { return criticalErrors; }
        public List<String> getReportFiles() { return reportFiles; }
        public int getErrorCount() { return errorCount; }
        
        public void setHasErrors(boolean hasErrors) { this.hasErrors = hasErrors; }
        public void setCriticalErrors(boolean criticalErrors) { this.criticalErrors = criticalErrors; }
        public void addReportFile(String filePath) { this.reportFiles.add(filePath); }
        public void setErrorCount(int count) { this.errorCount = count; }
    }
}
