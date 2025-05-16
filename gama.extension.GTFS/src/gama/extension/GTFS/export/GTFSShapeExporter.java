package gama.extension.GTFS.export;

import org.geotools.data.*;
import org.geotools.data.simple.SimpleFeatureStore;
import org.geotools.data.shapefile.ShapefileDataStore;
import org.geotools.data.shapefile.ShapefileDataStoreFactory;
import org.geotools.feature.DefaultFeatureCollection;
import org.geotools.feature.simple.SimpleFeatureBuilder;
import org.geotools.feature.simple.SimpleFeatureTypeBuilder;
import org.geotools.referencing.crs.DefaultGeographicCRS;
import org.locationtech.jts.geom.*;
import org.opengis.feature.simple.SimpleFeature;
import org.opengis.feature.simple.SimpleFeatureType;

import gama.core.runtime.IScope;
import gama.extension.GTFS.GTFS_reader;

import java.io.*;
import java.util.*;
import java.nio.charset.StandardCharsets;

public class GTFSShapeExporter {

    // --- Export principal (pour usage interne ou appel via Skill) ---
    public static void exportRouteShapesFromGTFS(File gtfsDir, String outputPath) throws Exception {
        // Lire shapes.txt, trips.txt, routes.txt
        Map<String, List<double[]>> shapePoints = new HashMap<>(); // shape_id -> List<lon, lat>
        Map<String, String> shapeToRoute = new HashMap<>(); // shape_id -> route_id
        Map<String, String> shapeToTrip = new HashMap<>(); // shape_id -> trip_id
        Map<String, Map<String, String>> routeInfo = new HashMap<>(); // route_id -> attributs

        // --- 1. Lecture de shapes.txt ---
        try (BufferedReader br = new BufferedReader(new FileReader(new File(gtfsDir, "shapes.txt"), StandardCharsets.UTF_8))) {
            String header = br.readLine();
            Map<String, Integer> colIdx = parseHeader(header);
            String line;
            while ((line = br.readLine()) != null) {
                String[] parts = line.split(",");
                String shapeId = parts[colIdx.get("shape_id")];
                double lat = Double.parseDouble(parts[colIdx.get("shape_pt_lat")]);
                double lon = Double.parseDouble(parts[colIdx.get("shape_pt_lon")]);
                shapePoints.computeIfAbsent(shapeId, k -> new ArrayList<>()).add(new double[]{lon, lat});
            }
        }

        // --- 2. Lecture de trips.txt ---
        try (BufferedReader br = new BufferedReader(new FileReader(new File(gtfsDir, "trips.txt"), StandardCharsets.UTF_8))) {
            String header = br.readLine();
            Map<String, Integer> colIdx = parseHeader(header);
            String line;
            while ((line = br.readLine()) != null) {
                String[] parts = line.split(",");
                String shapeId = parts[colIdx.get("shape_id")];
                String routeId = parts[colIdx.get("route_id")];
                String tripId = parts[colIdx.get("trip_id")];
                shapeToRoute.put(shapeId, routeId);
                shapeToTrip.put(shapeId, tripId);
            }
        }

        // --- 3. Lecture de routes.txt ---
        try (BufferedReader br = new BufferedReader(new FileReader(new File(gtfsDir, "routes.txt"), StandardCharsets.UTF_8))) {
            String header = br.readLine();
            Map<String, Integer> colIdx = parseHeader(header);
            String line;
            while ((line = br.readLine()) != null) {
                String[] parts = line.split(",");
                String routeId = parts[colIdx.get("route_id")];
                Map<String, String> attrs = new HashMap<>();
                attrs.put("route_type", parts[colIdx.get("route_type")]);
                attrs.put("route_color", parts[colIdx.get("route_color")]);
                attrs.put("route_short_name", parts[colIdx.get("route_short_name")]);
                attrs.put("route_long_name", parts[colIdx.get("route_long_name")]);
                routeInfo.put(routeId, attrs);
            }
        }

        // --- 4. Création du shapefile avec GeoTools ---
        SimpleFeatureTypeBuilder builder = new SimpleFeatureTypeBuilder();
        builder.setName("route");
        builder.setCRS(DefaultGeographicCRS.WGS84); // EPSG:4326
        builder.add("the_geom", LineString.class);
        builder.add("shape_id", String.class);
        builder.add("route_id", String.class);
        builder.add("trip_id", String.class);
        builder.add("route_type", String.class);
        builder.add("route_color", String.class);
        builder.add("route_short_name", String.class);
        builder.add("route_long_name", String.class);
        final SimpleFeatureType TYPE = builder.buildFeatureType();

        File newFile = new File(outputPath, "routes.shp");
        Map<String, Serializable> params = new HashMap<>();
        params.put("url", newFile.toURI().toURL());
        params.put("create spatial index", Boolean.TRUE);

        ShapefileDataStoreFactory dataStoreFactory = new ShapefileDataStoreFactory();
        ShapefileDataStore newDataStore = (ShapefileDataStore) dataStoreFactory.createNewDataStore(params);
        newDataStore.createSchema(TYPE);

        DefaultFeatureCollection collection = new DefaultFeatureCollection();
        GeometryFactory geomFactory = new GeometryFactory();

        for (String shapeId : shapePoints.keySet()) {
            List<double[]> points = shapePoints.get(shapeId);
            Coordinate[] coords = points.stream().map(arr -> new Coordinate(arr[0], arr[1])).toArray(Coordinate[]::new);
            LineString ls = geomFactory.createLineString(coords);

            SimpleFeatureBuilder featureBuilder = new SimpleFeatureBuilder(TYPE);
            featureBuilder.add(ls);
            featureBuilder.add(shapeId);
            featureBuilder.add(shapeToRoute.getOrDefault(shapeId, ""));
            featureBuilder.add(shapeToTrip.getOrDefault(shapeId, ""));
            String routeId = shapeToRoute.get(shapeId);
            Map<String, String> attrs = routeInfo.getOrDefault(routeId, new HashMap<>());
            featureBuilder.add(attrs.getOrDefault("route_type", ""));
            featureBuilder.add(attrs.getOrDefault("route_color", ""));
            featureBuilder.add(attrs.getOrDefault("route_short_name", ""));
            featureBuilder.add(attrs.getOrDefault("route_long_name", ""));
            collection.add(featureBuilder.buildFeature(null));
        }

        Transaction transaction = new DefaultTransaction("create");
        SimpleFeatureStore featureStore = (SimpleFeatureStore) newDataStore.getFeatureSource(newDataStore.getTypeNames()[0]);
        try {
            featureStore.setTransaction(transaction);
            featureStore.addFeatures(collection);
            transaction.commit();
            System.out.println("✅ Shapefile écrit : " + newFile.getAbsolutePath());
        } catch (Exception e) {
            transaction.rollback();
            throw e;
        } finally {
            transaction.close();
            newDataStore.dispose();
        }
    }

    // --- Surcharge pour appel depuis GAMA / Skill (avec IScope et GTFS_reader) ---
    public static void exportRouteShapesFromGTFS(IScope scope, GTFS_reader reader, String outputPath) throws Exception {
        File gtfsDir = reader.getFile(scope);
        exportRouteShapesFromGTFS(gtfsDir, outputPath);
    }

    // --- Utilitaire pour parser l'en-tête CSV ---
    private static Map<String, Integer> parseHeader(String headerLine) {
        Map<String, Integer> colIdx = new HashMap<>();
        String[] headers = headerLine.split(",");
        for (int i = 0; i < headers.length; i++) {
            colIdx.put(headers[i], i);
        }
        return colIdx;
    }

    // --- Pour tests console seulement (facultatif) ---
//    public static void main(String[] args) throws Exception {
//        File gtfsDir = new File("chemin/vers/ton/gtfs"); // <-- à adapter pour test hors GAMA
//        String outputPath = "chemin/vers/dossier/sortie";
//        exportRouteShapesFromGTFS(gtfsDir, outputPath);
//    }
}
