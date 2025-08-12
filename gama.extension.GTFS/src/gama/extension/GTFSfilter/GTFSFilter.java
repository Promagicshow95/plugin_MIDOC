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

     // --- stop_times.txt (TRI + RÉINDEX PAR TRIP) ---
        System.out.println("🔄 Filtrage/tri/réindex des horaires (stop_times.txt)...");
        StopTimesResult stRes = filterSortRenumberStopTimes(gtfsDir, outDir, keptStopIds);
        Set<String> keptTripIds = stRes.tripIds;                    // trips encore valides (>= 2 stops)
        Set<String> usedStopsAfter = stRes.stopIds;                 // stops réellement utilisés après réindex
        System.out.println("✅ stop_times.txt écrit. Trips gardés: " + keptTripIds.size());
        
     // ✅ Overwrite stops.txt to keep only stops that are still referenced after reindex
        filterAndWriteFile("stops.txt", gtfsDir, outDir, (header, row) -> {
            int idxStop = header.getOrDefault("stop_id", -1);
            if (idxStop < 0 || row.length <= idxStop) return false;
            return usedStopsAfter.contains(row[idxStop]);
        });



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
                if (idxShapeId >= 0 && row[idxShapeId] != null && !row[idxShapeId].isBlank()) {
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

       
     // --- shapes.txt : garder TOUTE shape référencée + trier par sequence + s'assurer que shape_id est numérique
        File shapesFile = new File(gtfsDir, "shapes.txt");
        Map<String,String> shapeIdRemap = new LinkedHashMap<>(); // oldSid -> new numeric string

        if (shapesFile.exists()) {
            System.out.println("🔄 Préparation shapes : garder toutes les shapes référencées par trips, triées par sequence, mapping numérique si nécessaire...");
            char sep = detectSeparator(shapesFile);

            // 1) lire toutes les lignes et regrouper par shape_id
            Map<String,Integer> head = new HashMap<>();
            String[] headerRow = null;
            int iId, iLat, iLon, iSeq;

            Map<String, List<String[]>> byShape = new HashMap<>();
            try (CSVReader r = new CSVReaderBuilder(new FileReader(shapesFile))
                    .withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build()) {
                headerRow = r.readNext();
                if (headerRow == null) throw new IOException("shapes.txt vide");
                for (int i=0;i<headerRow.length;i++) head.put(headerRow[i].trim().toLowerCase(), i);
                iId  = head.getOrDefault("shape_id", -1);
                iLat = head.getOrDefault("shape_pt_lat", -1);
                iLon = head.getOrDefault("shape_pt_lon", -1);
                iSeq = head.getOrDefault("shape_pt_sequence", -1);
                if (iId<0 || iLat<0 || iLon<0) throw new IOException("Colonnes shape_id / shape_pt_lat / shape_pt_lon requises");

                String[] row;
                while ((row = r.readNext()) != null) {
                    if (row.length <= Math.max(iLon, iLat)) continue;
                    String sid = row[iId];
                    if (!shapesToKeep.contains(sid)) continue; // uniquement les shapes référencées par les trips filtrés
                    byShape.computeIfAbsent(sid, k -> new ArrayList<>()).add(row);
                }
            }

            // 2) construire un mapping numérique si nécessaire (si au moins un shape_id n'est pas un int)
            boolean needsNumeric = shapesToKeep.stream().anyMatch(s -> {
                try { Integer.parseInt(s.trim()); return false; } catch (Exception e) { return true; }
            });
            int nextSid = 1;
            for (String sid : shapesToKeep) {
                String newSid = needsNumeric ? String.valueOf(nextSid++) : sid.trim();
                shapeIdRemap.put(sid, newSid);
            }

            // 3) écrire shapes.txt trié par sequence et avec shape_id remappé si besoin
            File out = new File(outDir, "shapes.txt");
            try (BufferedWriter w = Files.newBufferedWriter(out.toPath())) {
                w.write(String.join(String.valueOf(sep), headerRow));
                w.newLine();

                int kept = 0, total = 0;
                for (String sid : shapesToKeep) {
                    List<String[]> rows = byShape.get(sid);
                    if (rows == null || rows.isEmpty()) continue;
                    // tri par shape_pt_sequence si dispo, sinon ordre original
                    if (iSeq >= 0) {
                        rows.sort((a,b) -> {
                            try {
                                int sa = Integer.parseInt(a[iSeq].trim());
                                int sb = Integer.parseInt(b[iSeq].trim());
                                return Integer.compare(sa, sb);
                            } catch (Exception e) { return 0; }
                        });
                    }
                    String newSid = shapeIdRemap.get(sid);
                    for (String[] r : rows) {
                        r[iId] = newSid;
                        w.write(String.join(String.valueOf(sep), r));
                        w.newLine();
                        kept++; total++;
                    }
                }
                System.out.println("✅ shapes.txt écrit : " + kept + " lignes (triées), shapes=" + shapesToKeep.size() + ", mapping numérique=" + needsNumeric);
            }

            // 4) si on a remappé, remapper aussi trips.txt (champ shape_id)
            if (needsNumeric) {
                remapShapeIdsInTrips(new File(outDir, "trips.txt"), shapeIdRemap);
            }
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

        // -----------------------
        // AJOUT ICI POUR N'AVOIR QU'UN SEUL DOSSIER FINAL
        // -----------------------
        String cleanedDir = outputDirPath + "_cleaned";
        System.out.println("🔄 Nettoyage avec OneBusAway...");
        cleanWithOneBusAway(outputDirPath, cleanedDir);

        // Supprimer l'ancien dossier filtré brut (outputDirPath)
        deleteDirectoryRecursively(new File(outputDirPath));
        // Renommer le dossier nettoyé comme dossier final
        boolean ok = new File(cleanedDir).renameTo(new File(outputDirPath));
        if (!ok) {
            System.err.println("⚠️ Erreur lors du renommage du dossier nettoyé !");
        }
        
        try {
            postSortShapes(new File(outputDirPath));
        } catch (Exception e) {
            System.err.println("⚠️ postSortShapes a échoué: " + e.getMessage());
        }

        // Validation sur le dossier FINAL
        System.out.println("🔄 Validation avec GTFS-Validator...");
        ValidationResult result = validateWithGtfsValidator(outputDirPath);

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
        System.out.println("📁 Résultats dans: " + outputDirPath);
    }
    
    private static void postSortShapes(File outDir) throws IOException, CsvValidationException {
        File shapes = new File(outDir, "shapes.txt");
        if (!shapes.exists()) return;
        char sep = detectSeparator(shapes);

        List<String[]> rows = new ArrayList<>();
        String[] header;
        Map<String,Integer> idx;

        try (CSVReader r = new CSVReaderBuilder(new FileReader(shapes))
                .withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build()) {
            header = r.readNext();
            if (header == null) return;
            idx = parseHeader(header);
            String[] row;
            while ((row = r.readNext()) != null) rows.add(row);
        }

        int iId  = idx.getOrDefault("shape_id", -1);
        int iSeq = idx.getOrDefault("shape_pt_sequence", -1);

        rows.sort((a,b) -> {
            int c = a[iId].compareTo(b[iId]);
            if (c != 0) return c;
            if (iSeq < 0) return 0;
            try {
                int sa = Integer.parseInt(a[iSeq].trim());
                int sb = Integer.parseInt(b[iSeq].trim());
                return Integer.compare(sa, sb);
            } catch (Exception e) { return 0; }
        });

        File tmp = new File(shapes.getAbsolutePath() + ".tmp");
        try (BufferedWriter w = Files.newBufferedWriter(tmp.toPath())) {
            w.write(String.join(String.valueOf(sep), header));
            w.newLine();
            for (String[] row : rows) {
                w.write(String.join(String.valueOf(sep), row));
                w.newLine();
            }
        }
        Files.move(tmp.toPath(), shapes.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        System.out.println("✅ shapes.txt post-trié (shape_id, shape_pt_sequence)");
    }

    
    private static void remapShapeIdsInTrips(File tripsOutFile, Map<String,String> shapeIdRemap) throws IOException, CsvValidationException {
        if (!tripsOutFile.exists()) return;
        char sep = detectSeparator(tripsOutFile);

        File tmp = new File(tripsOutFile.getAbsolutePath() + ".tmp");
        try (CSVReader r = new CSVReaderBuilder(new FileReader(tripsOutFile))
                .withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build();
             BufferedWriter w = Files.newBufferedWriter(tmp.toPath())) {

            String[] header = r.readNext();
            if (header == null) return;
            w.write(String.join(String.valueOf(sep), header));
            w.newLine();

            Map<String,Integer> idx = parseHeader(header);
            int iShape = idx.getOrDefault("shape_id", -1);

            String[] row;
            while ((row = r.readNext()) != null) {
                if (iShape >= 0 && row.length > iShape) {
                    String oldSid = row[iShape];
                    if (shapeIdRemap.containsKey(oldSid)) {
                        row[iShape] = shapeIdRemap.get(oldSid);
                    }
                }
                w.write(String.join(String.valueOf(sep), row));
                w.newLine();
            }
        }
        Files.move(tmp.toPath(), tripsOutFile.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        System.out.println("✅ trips.txt remappé avec shape_id numériques");
    }


    private static void handleAgencyFile(File gtfsDir, File outDir, String osmFilePath) throws IOException {
        File agencySrc = new File(gtfsDir, "agency.txt");
        File agencyDest = new File(outDir, "agency.txt");

        if (agencySrc.exists() && agencySrc.length() > 0) {
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

    public static void cleanWithOneBusAway(String filteredInput, String outputDir) throws Exception {
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

            File outputDirFile = new File(outputDir);
            if (!outputDirFile.exists()) {
                outputDirFile.mkdirs();
            }

            GtfsWriter writer = new GtfsWriter();
            writer.setOutputLocation(outputDirFile);
            writer.run(dao);
            writer.close();

            System.out.println("✅ OneBusAway : GTFS nettoyé -> " + outputDir);

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
    static class StopTimesResult {
        Set<String> tripIds = new HashSet<>();
        Set<String> stopIds = new HashSet<>();
    }
    
    private static Map<String, Integer> parseHeader(String[] headers) {
        Map<String, Integer> m = new HashMap<>();
        for (int i = 0; i < headers.length; i++) {
            m.put(headers[i].trim().toLowerCase(), i);
        }
        return m;
    }
    
    private static StopTimesResult filterSortRenumberStopTimes(File gtfsDir, File outDir, Set<String> keptStopIds) throws Exception {
        StopTimesResult res = new StopTimesResult();
        File inFile = new File(gtfsDir, "stop_times.txt");
        if (!inFile.exists()) throw new FileNotFoundException("stop_times.txt manquant");
        char sep = detectSeparator(inFile);

        // lecture
        Map<String, Integer> idx;
        List<String[]> allRows = new ArrayList<>();
        
          // On lit le header pour déterminer les index des colonnes
        String[] headerRow = null;
        
        try (CSVReader r = new CSVReaderBuilder(new FileReader(inFile))
                .withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build()) {
        	headerRow = r.readNext();
        	if (headerRow == null) throw new IOException("stop_times.txt vide");
        	idx = parseHeader(headerRow);
            String[] row;
            while ((row = r.readNext()) != null) allRows.add(row);
        }

        int iTrip = idx.getOrDefault("trip_id", -1);
        int iStop = idx.getOrDefault("stop_id", -1);
        int iSeq  = idx.getOrDefault("stop_sequence", -1);
        int iDep  = idx.getOrDefault("departure_time", -1);
        if (iTrip < 0 || iStop < 0 || iSeq < 0 || iDep < 0) {
            throw new IllegalStateException("Colonnes requises absentes de stop_times.txt");
        }

        // groupement par trip + filtre bbox
        Map<String, List<String[]>> byTrip = new HashMap<>();
        for (String[] row : allRows) {
            if (row.length <= Math.max(Math.max(iTrip,iStop), Math.max(iSeq,iDep))) continue;
            if (!keptStopIds.contains(row[iStop])) continue; // on garde seulement les stops dans la bbox
            byTrip.computeIfAbsent(row[iTrip], k -> new ArrayList<>()).add(row);
        }

     // écriture triée + réindexée
        File outFile = new File(outDir, "stop_times.txt");
        try (BufferedWriter w = new BufferedWriter(new FileWriter(outFile))) {
            // on réécrit bien le header original
        	w.write(String.join(String.valueOf(sep), headerRow));
            w.newLine();

            int tripsKept = 0, tripsDropped = 0, rowsWritten = 0;

            for (Map.Entry<String, List<String[]>> e : byTrip.entrySet()) {
                String tripId = e.getKey();
                List<String[]> L = e.getValue();

                // trier par stop_sequence (fallback léger si parse échoue)
                L.sort((a,b) -> {
                    try {
                        int sa = Integer.parseInt(a[iSeq].trim());
                        int sb = Integer.parseInt(b[iSeq].trim());
                        return Integer.compare(sa, sb);
                    } catch (Exception ex) {
                        return a[iDep].compareTo(b[iDep]);
                    }
                });

                // enlever doublons éventuels de stop_sequence
                List<String[]> uniq = new ArrayList<>();
                Integer lastSeq = null;
                for (String[] row : L) {
                    Integer cur = null;
                    try { cur = Integer.parseInt(row[iSeq].trim()); } catch (Exception ignore) {}
                    if (lastSeq != null && cur != null && cur.equals(lastSeq)) continue;
                    lastSeq = cur;
                    uniq.add(row);
                }

                if (uniq.size() < 2) { tripsDropped++; continue; } // on ne garde pas les trips à 0/1 stop

                // réindex 1..N
                int seq = 1;
                for (String[] row : uniq) {
                    row[iSeq] = String.valueOf(seq++);
                    w.write(String.join(String.valueOf(sep), row));
                    w.newLine();
                    rowsWritten++;
                    res.stopIds.add(row[iStop]);
                }
                res.tripIds.add(tripId);
                tripsKept++;
            }

            System.out.println("📊 stop_times réindexé: trips gardés=" + tripsKept + ", supprimés=" + tripsDropped + ", lignes écrites=" + rowsWritten);
        }
        return res;
    }

    public static ValidationResult validateWithGtfsValidator(String outputDirPath) throws Exception {
        File filteredDir = new File(outputDirPath);

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

        List<String> command = new ArrayList<>();
        command.add("java");
        command.add("-jar");
        command.add(validatorJar);
        command.add("--input");
        command.add(outputDirPath);

        ProcessBuilder pb = new ProcessBuilder(command);
        pb.directory(new File(outputDirPath).getParentFile());

        ByteArrayOutputStream stdout = new ByteArrayOutputStream();
        ByteArrayOutputStream stderr = new ByteArrayOutputStream();

        try {
            Process proc = pb.start();

            Thread stdoutThread = new Thread(() -> {
                try (InputStream is = proc.getInputStream()) {
                    is.transferTo(stdout);
                } catch (IOException e) {
                }
            });

            Thread stderrThread = new Thread(() -> {
                try (InputStream is = proc.getErrorStream()) {
                    is.transferTo(stderr);
                } catch (IOException e) {
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

            return analyzeValidationResults(validationDir, code, stdoutStr, stderrStr);

        } catch (Exception e) {
            throw new RuntimeException("Erreur lors de l'exécution du GTFS-Validator: " + e.getMessage(), e);
        }
    }

    private static ValidationResult analyzeValidationResults(File validationDir, int exitCode,
                                                           String stdout, String stderr) {
        ValidationResult result = new ValidationResult(validationDir.getAbsolutePath(), exitCode);

        File[] reportFiles = validationDir.listFiles((dir, name) ->
            name.endsWith(".json") || name.endsWith(".html") || name.endsWith(".txt"));

        if (reportFiles != null) {
            for (File reportFile : reportFiles) {
                result.addReportFile(reportFile.getAbsolutePath());
                System.out.println("📋 Rapport trouvé: " + reportFile.getName());
            }
        }

        if (exitCode != 0) {
            result.setHasErrors(true);

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

    // --------------------------
    // AJOUT : suppression d’un dossier récursivement
    // --------------------------
    public static void deleteDirectoryRecursively(File dir) {
        if (dir.isDirectory()) {
            for (File file : dir.listFiles()) {
                deleteDirectoryRecursively(file);
            }
        }
        dir.delete();
    }
}
