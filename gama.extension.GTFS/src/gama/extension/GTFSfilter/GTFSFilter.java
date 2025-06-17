package gama.extension.GTFSfilter;


import GamaGTFSUtils.OSMUtils;
import org.locationtech.jts.geom.Envelope;

import java.io.*;
import java.nio.file.Files;
import java.util.*;

/**
 * Utility to filter GTFS files based on the bounding box extracted from an OSM file.
 * The resulting filtered files are written to a new directory.
 */
public class GTFSFilter {

    /**
     * Filter the GTFS directory using the bounding box contained in the OSM file.
     * Only the most common files (stops, shapes, trips, stop_times and routes)
     * are filtered. Other files are copied as is.
     */
    public static void filter(String gtfsDirPath, String osmFilePath, String outputDirPath) throws Exception {
        Envelope env = OSMUtils.extractEnvelope(osmFilePath);

        File gtfsDir = new File(gtfsDirPath);
        if (!gtfsDir.isDirectory()) {
            throw new IllegalArgumentException("Invalid GTFS directory: " + gtfsDirPath);
        }
        File outDir = new File(outputDirPath);
        if (!outDir.exists()) outDir.mkdirs();

        // Filter stops
        Set<String> keptStopIds = new HashSet<>();
        File stopsFile = new File(gtfsDir, "stops.txt");
        if (stopsFile.exists()) {
            List<String> lines = Files.readAllLines(stopsFile.toPath());
            if (!lines.isEmpty()) {
                Map<String,Integer> idx = parseHeader(lines.get(0));
                List<String> out = new ArrayList<>();
                out.add(lines.get(0));
                for (int i = 1; i < lines.size(); i++) {
                    String[] parts = parseCsv(lines.get(i));
                    if (parts.length <= Math.max(idx.get("stop_lat"), idx.get("stop_lon"))) continue;
                    double lat = Double.parseDouble(parts[idx.get("stop_lat")]);
                    double lon = Double.parseDouble(parts[idx.get("stop_lon")]);
                    if (env.contains(lon, lat)) {
                        keptStopIds.add(parts[idx.get("stop_id")]);
                        out.add(lines.get(i));
                    }
                }
                Files.write(new File(outDir,"stops.txt").toPath(), out);
            }
        }

        // Filter shapes (optional)
        Set<String> keptShapeIds = new HashSet<>();
        File shapesFile = new File(gtfsDir, "shapes.txt");
        if (shapesFile.exists()) {
            List<String> lines = Files.readAllLines(shapesFile.toPath());
            if (!lines.isEmpty()) {
                Map<String,Integer> idx = parseHeader(lines.get(0));
                List<String> out = new ArrayList<>();
                out.add(lines.get(0));
                String currentShape = null;
                boolean keepCurrent = false;
                for (int i = 1; i < lines.size(); i++) {
                    String[] parts = parseCsv(lines.get(i));
                    String shapeId = parts[idx.get("shape_id")];
                    if (!shapeId.equals(currentShape)) {
                        currentShape = shapeId;
                        keepCurrent = false;
                    }
                    double lat = Double.parseDouble(parts[idx.get("shape_pt_lat")]);
                    double lon = Double.parseDouble(parts[idx.get("shape_pt_lon")]);
                    if (env.contains(lon, lat)) {
                        keepCurrent = true;
                    }
                    if (keepCurrent) {
                        keptShapeIds.add(shapeId);
                        out.add(lines.get(i));
                    }
                }
                Files.write(new File(outDir,"shapes.txt").toPath(), out);
            }
        }

        // Filter stop_times and remember remaining trips
        Set<String> keptTripIds = new HashSet<>();
        File stopTimesFile = new File(gtfsDir, "stop_times.txt");
        if (stopTimesFile.exists()) {
            List<String> lines = Files.readAllLines(stopTimesFile.toPath());
            if (!lines.isEmpty()) {
                Map<String,Integer> idx = parseHeader(lines.get(0));
                List<String> out = new ArrayList<>();
                out.add(lines.get(0));
                for (int i=1;i<lines.size();i++) {
                    String[] parts = parseCsv(lines.get(i));
                    String stopId = parts[idx.get("stop_id")];
                    if (keptStopIds.contains(stopId)) {
                        keptTripIds.add(parts[idx.get("trip_id")]);
                        out.add(lines.get(i));
                    }
                }
                Files.write(new File(outDir,"stop_times.txt").toPath(), out);
            }
        }

        // Filter trips
        File tripsFile = new File(gtfsDir, "trips.txt");
        Set<String> routesToKeep = new HashSet<>();
        if (tripsFile.exists()) {
            List<String> lines = Files.readAllLines(tripsFile.toPath());
            if (!lines.isEmpty()) {
                Map<String,Integer> idx = parseHeader(lines.get(0));
                List<String> out = new ArrayList<>();
                out.add(lines.get(0));
                for (int i=1;i<lines.size();i++) {
                    String[] parts = parseCsv(lines.get(i));
                    String tripId = parts[idx.get("trip_id")];
                    String shapeId = idx.containsKey("shape_id") ? parts[idx.get("shape_id")] : "";
                    if (keptTripIds.contains(tripId) || keptShapeIds.contains(shapeId)) {
                        out.add(lines.get(i));
                        routesToKeep.add(parts[idx.get("route_id")]);
                        keptTripIds.add(tripId);
                        if (!shapeId.isEmpty()) keptShapeIds.add(shapeId);
                    }
                }
                Files.write(new File(outDir,"trips.txt").toPath(), out);
            }
        }

        // Filter routes
        File routesFile = new File(gtfsDir, "routes.txt");
        if (routesFile.exists()) {
            List<String> lines = Files.readAllLines(routesFile.toPath());
            if (!lines.isEmpty()) {
                Map<String,Integer> idx = parseHeader(lines.get(0));
                List<String> out = new ArrayList<>();
                out.add(lines.get(0));
                for (int i=1;i<lines.size();i++) {
                    String[] parts = parseCsv(lines.get(i));
                    if (routesToKeep.contains(parts[idx.get("route_id")])) {
                        out.add(lines.get(i));
                    }
                }
                Files.write(new File(outDir,"routes.txt").toPath(), out);
            }
        }

        // Copy remaining files
        for (File f : Objects.requireNonNull(gtfsDir.listFiles())) {
            if (!f.isFile() || !f.getName().endsWith(".txt")) continue;
            if (Set.of("stops.txt","shapes.txt","trips.txt","stop_times.txt","routes.txt").contains(f.getName())) continue;
            Files.copy(f.toPath(), new File(outDir,f.getName()).toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private static Map<String,Integer> parseHeader(String headerLine) {
        Map<String,Integer> map = new HashMap<>();
        String[] cols = headerLine.split(",");
        for (int i=0;i<cols.length;i++) {
            map.put(cols[i].trim().toLowerCase(), i);
        }
        return map;
    }

    private static String[] parseCsv(String line) {
        return line.split(",");
    }
}