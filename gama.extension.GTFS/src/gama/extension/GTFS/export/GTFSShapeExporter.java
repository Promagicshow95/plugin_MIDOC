package gama.extension.GTFS.export;

import gama.core.runtime.IScope;
import gama.extension.GTFS.GTFS_reader;
import gama.extension.GTFS.TransportStop;
import org.geotools.data.*;
import org.geotools.data.simple.SimpleFeatureStore;
import org.geotools.data.shapefile.ShapefileDataStore;
import org.geotools.data.shapefile.ShapefileDataStoreFactory;
import org.geotools.feature.DefaultFeatureCollection;
import org.geotools.feature.simple.SimpleFeatureBuilder;
import org.geotools.feature.simple.SimpleFeatureTypeBuilder;
import org.opengis.feature.simple.SimpleFeatureType;
import org.opengis.referencing.crs.CoordinateReferenceSystem;
import org.opengis.referencing.operation.MathTransform;
import org.geotools.referencing.CRS;
import org.locationtech.jts.geom.*;

import com.opencsv.CSVParserBuilder;
import com.opencsv.CSVReader;
import com.opencsv.CSVReaderBuilder;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class GTFSShapeExporter {

    private static final String WKT_GCS_WGS_1984 =
            "GEOGCS[\"GCS_WGS_1984\"," +
            "DATUM[\"D_WGS_1984\",SPHEROID[\"WGS_1984\",6378137.0,298.257223563]]," +
            "PRIMEM[\"Greenwich\",0.0]," +
            "UNIT[\"Degree\",0.0174532925199433]]";

    // Export GTFS (LineString si shapes.txt existe, sinon points d'arrêts)
    public static void exportGTFSAsShapefile(IScope scope, GTFS_reader reader, String outputPath) throws Exception {
        File gtfsDir = reader.getFile(scope);
        File shapesFile = new File(gtfsDir, "shapes.txt");

        if (shapesFile.exists()) {
            exportRouteShapesFromGTFS(gtfsDir, outputPath);
        } else {
            Collection<TransportStop> stops = reader.getStops();
            exportStopsAsShapefile(stops, outputPath);
        }
    }

    // Export des routes (LineString)
    public static void exportRouteShapesFromGTFS(File gtfsDir, String outputPath) throws Exception {
        Map<String, List<double[]>> shapePoints = new HashMap<>();
        Map<String, String> shapeToRoute = new HashMap<>();
        Map<String, String> shapeToTrip = new HashMap<>();
        Map<String, Map<String, String>> routeInfo = new HashMap<>();

        // 1. shapes.txt
        File shapesFile = new File(gtfsDir, "shapes.txt");
        if (!shapesFile.exists()) throw new IOException("shapes.txt non trouvé !");
        char sepShapes = detectSeparator(shapesFile);

        try (
            CSVReader reader = new CSVReaderBuilder(new InputStreamReader(new FileInputStream(shapesFile), StandardCharsets.UTF_8))
                .withCSVParser(new CSVParserBuilder().withSeparator(sepShapes).build())
                .build()
        ) {
            String[] header = reader.readNext();
            if (header == null) throw new IOException("shapes.txt vide");
            Map<String, Integer> idx = parseHeader(header);

            String[] line;
            while ((line = reader.readNext()) != null) {
                if (isLineTooShort(line, idx, "shape_id", "shape_pt_lat", "shape_pt_lon")) continue;
                String shapeId = line[idx.get("shape_id")];
                double lat, lon;
                try {
                    lat = Double.parseDouble(line[idx.get("shape_pt_lat")]);
                    lon = Double.parseDouble(line[idx.get("shape_pt_lon")]);
                } catch (Exception e) { continue; }
                shapePoints.computeIfAbsent(shapeId, k -> new ArrayList<>()).add(new double[]{lon, lat});
            }
        }

        // 2. trips.txt
        File tripsFile = new File(gtfsDir, "trips.txt");
        if (!tripsFile.exists()) throw new IOException("trips.txt non trouvé !");
        char sepTrips = detectSeparator(tripsFile);

        try (
            CSVReader reader = new CSVReaderBuilder(new InputStreamReader(new FileInputStream(tripsFile), StandardCharsets.UTF_8))
                .withCSVParser(new CSVParserBuilder().withSeparator(sepTrips).build())
                .build()
        ) {
            String[] header = reader.readNext();
            if (header == null) throw new IOException("trips.txt vide");
            Map<String, Integer> idx = parseHeader(header);

            String[] line;
            while ((line = reader.readNext()) != null) {
                if (isLineTooShort(line, idx, "shape_id", "route_id", "trip_id")) continue;
                String shapeId = line[idx.get("shape_id")];
                String routeId = line[idx.get("route_id")];
                String tripId = line[idx.get("trip_id")];
                if (shapeId != null && !shapeId.isEmpty()) {
                    shapeToRoute.put(shapeId, routeId);
                    shapeToTrip.put(shapeId, tripId);
                }
            }
        }

        // 3. routes.txt
        File routesFile = new File(gtfsDir, "routes.txt");
        if (!routesFile.exists()) throw new IOException("routes.txt non trouvé !");
        char sepRoutes = detectSeparator(routesFile);

        try (
            CSVReader reader = new CSVReaderBuilder(new InputStreamReader(new FileInputStream(routesFile), StandardCharsets.UTF_8))
                .withCSVParser(new CSVParserBuilder().withSeparator(sepRoutes).build())
                .build()
        ) {
            String[] header = reader.readNext();
            if (header == null) throw new IOException("routes.txt vide");
            Map<String, Integer> idx = parseHeader(header);

            String[] line;
            while ((line = reader.readNext()) != null) {
                if (!idx.containsKey("route_id")) continue;
                String routeId = getValue(line, idx, "route_id");
                Map<String, String> attrs = new HashMap<>();
                attrs.put("route_type", getValue(line, idx, "route_type"));
                attrs.put("route_color", getValue(line, idx, "route_color"));
                attrs.put("route_short_name", getValue(line, idx, "route_short_name"));
                attrs.put("route_long_name", getValue(line, idx, "route_long_name"));
                routeInfo.put(routeId, attrs);
            }
        }

        // 4. Création du shapefile (identique à ton code)
        CoordinateReferenceSystem crs = CRS.parseWKT(WKT_GCS_WGS_1984);

        SimpleFeatureTypeBuilder builder = new SimpleFeatureTypeBuilder();
        builder.setName("route");
        builder.setCRS(crs);
        builder.add("the_geom", LineString.class);
        builder.add("shape_id", String.class);
        builder.add("route_id", String.class);
        builder.add("trip_id", String.class);
        builder.add("route_type", String.class);
        builder.add("route_color", String.class);
        builder.add("route_short_name", String.class);
        builder.add("route_long_name", String.class);
        final SimpleFeatureType TYPE = builder.buildFeatureType();

        File newFile = new File(outputPath, "routes_wgs84.shp");
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
            System.out.println("✅ Shapefile écrit (GCS_WGS_1984, degrés) : " + newFile.getAbsolutePath());
        } catch (Exception e) {
            transaction.rollback();
            throw e;
        } finally {
            transaction.close();
            newDataStore.dispose();
        }
    }

    public static void exportStopsAsShapefile(Collection<TransportStop> stops, String outputPath) throws Exception {
        CoordinateReferenceSystem crs = CRS.parseWKT(WKT_GCS_WGS_1984);

        SimpleFeatureTypeBuilder builder = new SimpleFeatureTypeBuilder();
        builder.setName("stop");
        builder.setCRS(crs);
        builder.add("the_geom", Point.class);
        builder.add("stop_id", String.class);
        builder.add("stop_name", String.class);
        builder.add("route_type", Integer.class);
        final SimpleFeatureType TYPE = builder.buildFeatureType();

        File newFile = new File(outputPath, "stops_points_wgs84.shp");
        Map<String, Serializable> params = new HashMap<>();
        params.put("url", newFile.toURI().toURL());
        params.put("create spatial index", Boolean.TRUE);

        ShapefileDataStoreFactory dataStoreFactory = new ShapefileDataStoreFactory();
        ShapefileDataStore newDataStore = (ShapefileDataStore) dataStoreFactory.createNewDataStore(params);
        newDataStore.createSchema(TYPE);

        DefaultFeatureCollection collection = new DefaultFeatureCollection();
        GeometryFactory geomFactory = new GeometryFactory();

        for (TransportStop stop : stops) {
            Point pt = geomFactory.createPoint(new Coordinate(stop.getStopLon(), stop.getStopLat()));
            SimpleFeatureBuilder featureBuilder = new SimpleFeatureBuilder(TYPE);
            featureBuilder.add(pt);
            featureBuilder.add(stop.getStopId());
            featureBuilder.add(stop.getStopName());
            featureBuilder.add(stop.getRouteType());
            collection.add(featureBuilder.buildFeature(null));
        }

        Transaction transaction = new DefaultTransaction("create");
        SimpleFeatureStore featureStore = (SimpleFeatureStore) newDataStore.getFeatureSource(newDataStore.getTypeNames()[0]);
        try {
            featureStore.setTransaction(transaction);
            featureStore.addFeatures(collection);
            transaction.commit();
            System.out.println("✅ Shapefile écrit (GCS_WGS_1984, degrés) : " + newFile.getAbsolutePath());
        } catch (Exception e) {
            transaction.rollback();
            throw e;
        } finally {
            transaction.close();
            newDataStore.dispose();
        }
    }

    // --- Utilitaires robustes ---

    // Détection automatique du séparateur CSV
    private static char detectSeparator(File file) throws IOException {
        try (BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8))) {
            String line = r.readLine();
            if (line == null) return ',';
            if (line.contains(";")) return ';';
            if (line.contains("\t")) return '\t';
            return ',';
        }
    }

    // Parse header CSV, insensible à la casse et espaces
    private static Map<String, Integer> parseHeader(String[] headers) {
        Map<String, Integer> colIdx = new HashMap<>();
        for (int i = 0; i < headers.length; i++) {
            colIdx.put(headers[i].trim().toLowerCase(), i);
        }
        return colIdx;
    }

    // Vérifie la présence des colonnes obligatoires et qu'elles sont dans la ligne courante
    private static boolean isLineTooShort(String[] line, Map<String, Integer> idx, String... keys) {
        for (String key : keys) {
            Integer i = idx.get(key);
            if (i == null || line.length <= i) return true;
        }
        return false;
    }

    // Récupère une valeur de la colonne de façon sûre ("" si absente)
    private static String getValue(String[] line, Map<String, Integer> idx, String key) {
        Integer i = idx.get(key);
        if (i == null || i >= line.length) return "";
        return line[i];
    }
}
