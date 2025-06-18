package gama.extension.GTFSfilter;

import GamaGTFSUtils.OSMUtils;
import org.locationtech.jts.geom.Envelope;
import com.opencsv.CSVReader;
import com.opencsv.CSVParserBuilder;
import com.opencsv.CSVReaderBuilder;
import com.opencsv.exceptions.CsvValidationException;

import java.io.*;
import java.nio.file.Files;
import java.util.*;

public class GTFSFilter {

    public static void filter(String gtfsDirPath, String osmFilePath, String outputDirPath) throws Exception {
        Envelope env = OSMUtils.extractEnvelope(osmFilePath);

        File gtfsDir = new File(gtfsDirPath);
        if (!gtfsDir.isDirectory()) {
            throw new IllegalArgumentException("Invalid GTFS directory: " + gtfsDirPath);
        }
        File outDir = new File(outputDirPath);
        if (!outDir.exists()) outDir.mkdirs();

        // Filtrage des stops
        Set<String> keptStopIds = new HashSet<>();
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
            } catch (Exception e) {}
            return false;
        });

        // Filtrage des shapes
        Set<String> keptShapeIds = new HashSet<>();
        filterAndWriteFile("shapes.txt", gtfsDir, outDir, (header, row) -> {
            int idxLat = header.getOrDefault("shape_pt_lat", -1);
            int idxLon = header.getOrDefault("shape_pt_lon", -1);
            int idxShapeId = header.getOrDefault("shape_id", -1);
            if (row.length <= Math.max(idxLat, idxLon) || idxLat < 0 || idxLon < 0 || idxShapeId < 0) return false;
            try {
                double lat = Double.parseDouble(row[idxLat]);
                double lon = Double.parseDouble(row[idxLon]);
                if (env.contains(lon, lat)) {
                    keptShapeIds.add(row[idxShapeId]);
                    return true;
                }
            } catch (Exception e) {}
            return false;
        });

        // stop_times et keptTripIds
        Set<String> keptTripIds = new HashSet<>();
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

        // trips et routesToKeep
        Set<String> routesToKeep = new HashSet<>();
        filterAndWriteFile("trips.txt", gtfsDir, outDir, (header, row) -> {
            int idxTripId = header.getOrDefault("trip_id", -1);
            int idxShapeId = header.getOrDefault("shape_id", -1);
            int idxRouteId = header.getOrDefault("route_id", -1);
            if (row.length <= Math.max(idxTripId, idxRouteId) || idxTripId < 0 || idxRouteId < 0) return false;
            String tripId = row[idxTripId];
            String shapeId = (idxShapeId >= 0 && row.length > idxShapeId) ? row[idxShapeId] : "";
            if (keptTripIds.contains(tripId) || (!shapeId.isEmpty() && keptShapeIds.contains(shapeId))) {
                routesToKeep.add(row[idxRouteId]);
                keptTripIds.add(tripId);
                if (!shapeId.isEmpty()) keptShapeIds.add(shapeId);
                return true;
            }
            return false;
        });

        // routes
        filterAndWriteFile("routes.txt", gtfsDir, outDir, (header, row) -> {
            int idxRouteId = header.getOrDefault("route_id", -1);
            if (row.length <= idxRouteId || idxRouteId < 0) return false;
            return routesToKeep.contains(row[idxRouteId]);
        });

        // Copy remaining files (inchangés)
        for (File f : Objects.requireNonNull(gtfsDir.listFiles())) {
            if (!f.isFile() || !f.getName().endsWith(".txt")) continue;
            if (Set.of("stops.txt","shapes.txt","trips.txt","stop_times.txt","routes.txt").contains(f.getName())) continue;
            Files.copy(f.toPath(), new File(outDir, f.getName()).toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        }
    }

    /**
     * Fonction utilitaire : filtre et écrit un fichier GTFS
     * @throws CsvValidationException 
     */
    private static void filterAndWriteFile(String filename, File inDir, File outDir, RowPredicate keepRow) throws IOException, CsvValidationException {
        File inFile = new File(inDir, filename);
        if (!inFile.exists()) return;

        char sep = detectSeparator(inFile);
        try (
            Reader reader = new BufferedReader(new FileReader(inFile));
            CSVReader csvReader = new CSVReaderBuilder(reader).withCSVParser(new CSVParserBuilder().withSeparator(sep).build()).build();
            BufferedWriter writer = Files.newBufferedWriter(new File(outDir, filename).toPath())
        ) {
            String[] header = csvReader.readNext();
            if (header == null) return;
            writer.write(String.join(String.valueOf(sep), header)); writer.newLine();
            Map<String, Integer> headerIdx = new HashMap<>();
            for (int i=0; i<header.length; i++) headerIdx.put(header[i].trim().toLowerCase(), i);

            String[] row;
            while ((row = csvReader.readNext()) != null) {
                if (row.length == 0) continue;
                if (keepRow.keep(headerIdx, row)) {
                    writer.write(String.join(String.valueOf(sep), row));
                    writer.newLine();
                }
            }
        }
    }

    // Détection automatique du séparateur
    private static char detectSeparator(File file) throws IOException {
        try (BufferedReader r = new BufferedReader(new FileReader(file))) {
            String line = r.readLine();
            if (line == null) return ',';
            if (line.contains(";")) return ';';
            if (line.contains("\t")) return '\t';
            return ',';
        }
    }

    @FunctionalInterface
    interface RowPredicate {
        boolean keep(Map<String, Integer> header, String[] row);
    }
}
