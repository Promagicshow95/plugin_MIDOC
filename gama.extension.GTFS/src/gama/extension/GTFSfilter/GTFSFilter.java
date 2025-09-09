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

import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.Geometry;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.LineString;
import org.locationtech.jts.linearref.LengthIndexedLine;


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

       
     // --- shapes.txt : sous-shape par trip (clippée bbox) ---
        File shapesSrc = new File(gtfsDir, "shapes.txt");
        GeometryFactory GF = new GeometryFactory();

        // 0) Index utilitaires à construire

        // 0.1 stopsMap: stop_id -> (lat, lon) depuis stops.txt (filtré)
        Map<String, Coordinate> stopsCoord = new HashMap<>();
        {
            File stopsOut = new File(outDir, "stops.txt");
            if (stopsOut.exists()) {
                char sep = detectSeparator(stopsOut);
                try (CSVReader r = new CSVReaderBuilder(new FileReader(stopsOut))
                        .withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build()) {
                    String[] h = r.readNext();
                    if (h != null) {
                        Map<String,Integer> idx = parseHeader(h);
                        int iId  = idx.getOrDefault("stop_id", -1);
                        int iLat = idx.getOrDefault("stop_lat", -1);
                        int iLon = idx.getOrDefault("stop_lon", -1);
                        String[] row;
                        while ((row = r.readNext()) != null) {
                            if (row.length > Math.max(iLon,iLat) && iId>=0) {
                                String sid = row[iId].trim();
                                try {
                                    double lat = Double.parseDouble(row[iLat]);
                                    double lon = Double.parseDouble(row[iLon]);
                                    stopsCoord.put(sid, new Coordinate(lon, lat)); // JTS: x=lon, y=lat
                                } catch (NumberFormatException e) {
                                    System.err.println("Erreur parsing lat/lon pour stop " + sid + ": " + e.getMessage());
                                } catch (Exception e) {
                                    System.err.println("Erreur inattendue stop " + sid + ": " + e.getMessage());
                                }
                            }
                        }
                    }
                }
            }
        }

        // 0.2 byTrip: trip_id -> liste ordonnée des arrêts gardés (avec lat/lon) depuis stop_times.txt (filtré)
        Map<String, List<StopRef>> byTrip = new HashMap<>();
        {
            File stOut = new File(outDir, "stop_times.txt");
            char sep = detectSeparator(stOut);
            try (CSVReader r = new CSVReaderBuilder(new FileReader(stOut))
                    .withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build()) {
                String[] h = r.readNext();
                if (h == null) throw new IOException("stop_times.txt vide (outDir)");
                Map<String,Integer> idx = parseHeader(h);
                int iTrip = idx.getOrDefault("trip_id", -1);
                int iStop = idx.getOrDefault("stop_id", -1);
                int iSeq  = idx.getOrDefault("stop_sequence", -1);
                String[] row;
                while ((row = r.readNext()) != null) {
                    if (row.length <= Math.max(iTrip, Math.max(iStop, iSeq))) continue;
                    String trip = row[iTrip].trim();
                    String sid  = row[iStop].trim();
                    Coordinate c = stopsCoord.get(sid);
                    if (c == null) continue; // stop absent (sécurité)
                    byTrip.computeIfAbsent(trip, k -> new ArrayList<>())
                          .add(new StopRef(sid, c.y, c.x)); // (lat,lon)
                }
            }
            // trier par stop_sequence (déjà réindexé, mais au cas où)
            for (List<StopRef> L : byTrip.values()) {
                // rien à faire ici car on n'a pas stocké stop_sequence; stop_times.txt filtré l'a déjà remis en ordre
                // si besoin: relire stop_sequence et trier; ici on suppose outFile déjà trié
            }
        }

        // 0.3 tripToShapeId (depuis trips.txt filtré)
        Map<String,String> tripToShapeId = new HashMap<>();
        {
            File tripsOut = new File(outDir, "trips.txt");
            char sep = detectSeparator(tripsOut);
            try (CSVReader r = new CSVReaderBuilder(new FileReader(tripsOut))
                    .withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build()) {
                String[] h = r.readNext();
                if (h != null) {
                    Map<String,Integer> idx = parseHeader(h);
                    int iTrip  = idx.getOrDefault("trip_id", -1);
                    int iShape = idx.getOrDefault("shape_id", -1);
                    String[] row;
                    while ((row = r.readNext()) != null) {
                        if (iTrip >= 0 && row.length > iTrip) {
                            String t = row[iTrip].trim();
                            String s = (iShape >= 0 && row.length > iShape) ? row[iShape].trim() : null;
                            if (s != null && !s.isEmpty()) tripToShapeId.put(t, s);
                        }
                    }
                }
            }
        }

        // 0.4 byShape: shape_id -> liste ordonnée de Coordinates (x=lon,y=lat) depuis shapes.txt source (si existe)
        Map<String, List<Coordinate>> byShape = new HashMap<>();
        if (shapesSrc.exists()) {
            char sep = detectSeparator(shapesSrc);
            try (CSVReader r = new CSVReaderBuilder(new FileReader(shapesSrc))
                    .withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build()) {
                String[] h = r.readNext();
                if (h != null) {
                    Map<String,Integer> idx = parseHeader(h);
                    int iId  = idx.getOrDefault("shape_id", -1);
                    int iLat = idx.getOrDefault("shape_pt_lat", -1);
                    int iLon = idx.getOrDefault("shape_pt_lon", -1);
                    int iSeq = idx.getOrDefault("shape_pt_sequence", -1);
                    Map<String, List<String[]>> tmp = new HashMap<>();
                    String[] row;
                    while ((row = r.readNext()) != null) {
                        if (iId<0 || iLat<0 || iLon<0) continue;
                        String sid = row[iId];
                        tmp.computeIfAbsent(sid, k -> new ArrayList<>()).add(row);
                    }
                    for (Map.Entry<String,List<String[]>> e : tmp.entrySet()) {
                        List<String[]> rows = e.getValue();
                        if (iSeq >= 0) {
                            rows.sort((a,b) -> {
                                try {
                                    int sa = Integer.parseInt(a[iSeq].trim());
                                    int sb = Integer.parseInt(b[iSeq].trim());
                                    return Integer.compare(sa, sb);
                                } catch (Exception ex) { return 0; }
                            });
                        }
                        List<Coordinate> coords = new ArrayList<>();
                        for (String[] rr : rows) {
                            try {
                                double lat = Double.parseDouble(rr[iLat]);
                                double lon = Double.parseDouble(rr[iLon]);
                                coords.add(new Coordinate(lon, lat));
                            } catch (NumberFormatException ex) {
                                System.err.println("Erreur parsing lat/lon pour shape " + e.getKey() + ": " + ex.getMessage());
                            } catch (Exception ex) {
                                System.err.println("Erreur inattendue shape " + e.getKey() + ": " + ex.getMessage());
                            }
                        }
                        if (coords.size() >= 2) byShape.put(e.getKey(), coords);
                    }
                }
            }
        }

     // 1) Écrire la nouvelle shapes.txt (tous les tronçons internes à la bbox, ordonnés)
        File outShapes = new File(outDir, "shapes.txt");
        try (BufferedWriter w = Files.newBufferedWriter(outShapes.toPath())) {

            // -- 1a) Choisir un séparateur de sortie cohérent avec les autres fichiers écrits
            char outSep = ',';
            for (String probe : List.of("stops.txt","trips.txt","routes.txt","stop_times.txt")) {
                File f = new File(outDir, probe);
                if (f.exists()) { outSep = detectSeparator(f); break; }
            }

            // -- 1b) Écrire le header en utilisant ce séparateur
            w.write("shape_id" + outSep + "shape_pt_lat" + outSep + "shape_pt_lon" + outSep + "shape_pt_sequence");
            w.newLine();

            int nextNewShapeId = 1;
            Map<String,String> tripToNewShape = new HashMap<>();
            int written = 0;

            for (String tripId : keptTripIds) {
                List<StopRef> stops = byTrip.get(tripId);
                if (stops == null || stops.size() < 2) continue;

                String newSid = String.valueOf(nextNewShapeId++);
                tripToNewShape.put(tripId, newSid);

                int seq = 1;              // compteur shape_pt_sequence
                boolean wroteAny = false; // avons-nous écrit au moins un point ?

                // -- 1c) Si on a une shape source : sous-ligne (1er -> dernier stop) puis clip bbox
                String origSid = tripToShapeId.get(tripId);
                if (origSid != null) {
                    List<Coordinate> coords = byShape.get(origSid);
                    if (coords != null && coords.size() >= 2) {
                        LineString full = toLineString(GF, coords);

                        StopRef sFirst = stops.get(0), sLast = stops.get(stops.size()-1);
                        Coordinate cFirst = new Coordinate(sFirst.lon, sFirst.lat); // x=lon,y=lat
                        Coordinate cLast  = new Coordinate(sLast.lon,  sLast.lat);

                        LineString sub = subLineBetweenStops(full, cFirst, cLast);
                        if (sub != null && !sub.isEmpty()) {
                            LengthIndexedLine lil = new LengthIndexedLine(sub);
                            Geometry clipped = clipToBbox(sub, env, GF);

                            // -- 1d) Récupérer TOUS les LineString internes à la bbox
                            List<LineString> parts = new ArrayList<>();
                            List<Double> starts = new ArrayList<>();

                            if (clipped instanceof LineString) {
                                LineString ls = (LineString) clipped;
                                if (!ls.isEmpty()) {
                                    parts.add(ls);
                                    starts.add(lil.project(ls.getCoordinateN(0)));
                                }
                            } else {
                                for (int i = 0; i < clipped.getNumGeometries(); i++) {
                                    Geometry gi = clipped.getGeometryN(i);
                                    if (gi instanceof LineString && !gi.isEmpty()) {
                                        LineString ls = (LineString) gi;
                                        parts.add(ls);
                                        starts.add(lil.project(ls.getCoordinateN(0)));
                                    }
                                }
                            }

                            // -- 1e) Ordonner les morceaux selon leur position le long de 'sub'
                            List<Integer> order = new ArrayList<>();
                            for (int i = 0; i < parts.size(); i++) order.add(i);
                            order.sort(Comparator.comparingDouble(starts::get));

                            // -- 1f) Écrire tous les points, sans doublon consécutif
                            Coordinate last = null;
                            for (int k : order) {
                                Coordinate[] pc = parts.get(k).getCoordinates();
                                for (Coordinate c : pc) {
                                    if (last != null && last.equals2D(c)) continue;
                                    String[] row = new String[] {
                                        newSid,
                                        String.valueOf(c.y),      // lat
                                        String.valueOf(c.x),      // lon
                                        String.valueOf(seq++)
                                    };
                                    w.write(String.join(String.valueOf(outSep), row));
                                    w.newLine();
                                    written++;
                                    wroteAny = true;
                                    last = c;
                                }
                            }
                        }
                    }
                }

                // -- 1g) Fallback : si rien écrit (pas de shape source utilisable), relier les arrêts
                if (!wroteAny) {
                    List<Coordinate> seqStops = new ArrayList<>();
                    for (StopRef s : stops) seqStops.add(new Coordinate(s.lon, s.lat));
                    if (seqStops.size() >= 2) {
                        Coordinate[] out = toLineString(GF, seqStops).getCoordinates();
                        for (Coordinate c : out) {
                            String[] row = new String[] {
                                newSid,
                                String.valueOf(c.y),          // lat
                                String.valueOf(c.x),          // lon
                                String.valueOf(seq++)
                            };
                            w.write(String.join(String.valueOf(outSep), row));
                            w.newLine();
                            written++;
                        }
                    }
                }
            }

            System.out.println("✅ shapes.txt écrit (tous tronçons intra-bbox) : " + written + " lignes, shapes=" + (nextNewShapeId-1));

            // -- 1h) Remapper trips.txt -> nouveau shape_id
            remapTripsShapeIdsPerTrip(new File(outDir, "trips.txt"), tripToNewShape);
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
    
 // Helpers simples
    static class StopRef { String stopId; double lat, lon; StopRef(String s,double la,double lo){stopId=s;lat=la;lon=lo;} }
    
    private static LineString subLineBetweenStops(LineString line, Coordinate a, Coordinate b) {
        LengthIndexedLine lil = new LengthIndexedLine(line);
        double ia = lil.project(a), ib = lil.project(b);
        double from = Math.min(ia, ib), to = Math.max(ia, ib);
        return (LineString) lil.extractLine(from, to);
    }


    private static LineString toLineString(GeometryFactory gf, List<Coordinate> coords) {
        return gf.createLineString(coords.toArray(new Coordinate[0]));
    }

    private static Geometry clipToBbox(Geometry g, Envelope env, GeometryFactory gf) {
        Geometry bbox = gf.toGeometry(env);
        return g.intersection(bbox);
    }

    private static LineString longestLine(Geometry geom, GeometryFactory gf) {
        if (geom == null || geom.isEmpty()) return null;
        if (geom instanceof LineString) return (LineString) geom;
        double best = -1; LineString pick = null;
        for (int i=0;i<geom.getNumGeometries();i++) {
            Geometry gi = geom.getGeometryN(i);
            if (gi instanceof LineString) {
                double L = gi.getLength();
                if (L > best) { best = L; pick = (LineString) gi; }
            }
        }
        return pick;
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
            } catch (Exception e) {
                System.err.println("Erreur parsing stop_sequence: " + e.getMessage());
                return 0;
            }
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
    
    private static void remapTripsShapeIdsPerTrip(File tripsFile, Map<String,String> tripToNewShape)
            throws IOException, CsvValidationException {
        if (!tripsFile.exists()) return;
        char sep = detectSeparator(tripsFile);
        File tmp = new File(tripsFile.getAbsolutePath() + ".tmp");

        try (CSVReader r = new CSVReaderBuilder(new FileReader(tripsFile))
                .withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build();
             BufferedWriter w = Files.newBufferedWriter(tmp.toPath())) {

            String[] header = r.readNext();
            if (header == null) return;
            w.write(String.join(String.valueOf(sep), header));
            w.newLine();

            Map<String,Integer> idx = parseHeader(header);
            int iTrip  = idx.getOrDefault("trip_id", -1);
            int iShape = idx.getOrDefault("shape_id", -1);

            String[] row;
            while ((row = r.readNext()) != null) {
                if (iTrip >= 0 && iShape >= 0 && row.length > Math.max(iTrip,iShape)) {
                    String t = row[iTrip].trim();
                    String newSid = tripToNewShape.get(t);
                    if (newSid != null) row[iShape] = newSid;
                }
                w.write(String.join(String.valueOf(sep), row));
                w.newLine();
            }
        }
        Files.move(tmp.toPath(), tripsFile.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        System.out.println("✅ trips.txt remappé avec shape_id par trip");
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
