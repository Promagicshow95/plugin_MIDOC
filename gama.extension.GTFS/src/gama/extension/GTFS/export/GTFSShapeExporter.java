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
import org.geotools.geometry.jts.JTS;
import org.geotools.referencing.CRS;
import org.opengis.feature.simple.SimpleFeatureType;
import org.opengis.referencing.crs.CoordinateReferenceSystem;
import org.opengis.referencing.operation.MathTransform;
import org.locationtech.jts.geom.*;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/**
 * GTFSShapeExporter : Exporte les shapes/routes (LineString) ou arrêts (Points) du GTFS en shapefile
 * CRS du shapefile : EPSG:4326 (WGS 84, longitude/latitude en degrés décimaux)
 * IMPORTANT : Vérifier que les coordonnées fournies sont bien en degrés, sinon les convertir AVANT d’appeler cette classe.
 * Compatible avec GAMA, QGIS, ArcGIS, etc.
 */
public class GTFSShapeExporter {

    // --- WKT du CRS attendu
    private static final String WKT_GCS_WGS_1984 =
            "GEOGCS[\"GCS_WGS_1984\"," +
            "DATUM[\"D_WGS_1984\",SPHEROID[\"WGS_1984\",6378137.0,298.257223563]]," +
            "PRIMEM[\"Greenwich\",0.0]," +
            "UNIT[\"Degree\",0.0174532925199433]]";

    // --- Export GTFS sous forme de routes (LineString) si shapes.txt existe, sinon arrêts (Points) ---
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

    // --- Export des routes (LineString) à partir de shapes.txt, trips.txt, routes.txt ---
    public static void exportRouteShapesFromGTFS(File gtfsDir, String outputPath) throws Exception {
        Map<String, List<double[]>> shapePoints = new HashMap<>();
        Map<String, String> shapeToRoute = new HashMap<>();
        Map<String, String> shapeToTrip = new HashMap<>();
        Map<String, Map<String, String>> routeInfo = new HashMap<>();

        // 1. Lecture de shapes.txt
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

        // 2. Lecture de trips.txt
        try (BufferedReader br = new BufferedReader(new FileReader(new File(gtfsDir, "trips.txt"), StandardCharsets.UTF_8))) {
            String header = br.readLine();
            Map<String, Integer> colIdx = parseHeader(header);
            String line;
            while ((line = br.readLine()) != null) {
                String[] parts = line.split(",");
                String shapeId = parts[colIdx.get("shape_id")];
                String routeId = parts[colIdx.get("route_id")];
                String tripId = parts[colIdx.get("trip_id")];
                if (shapeId != null) {
                    shapeToRoute.put(shapeId, routeId);
                    shapeToTrip.put(shapeId, tripId);
                }
            }
        }

        // 3. Lecture de routes.txt
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

        // 4. Création du CRS à partir du WKT (à la place de DefaultGeographicCRS.WGS84)
        CoordinateReferenceSystem crs = CRS.parseWKT(WKT_GCS_WGS_1984);

        SimpleFeatureTypeBuilder builder = new SimpleFeatureTypeBuilder();
        builder.setName("route");
        builder.setCRS(crs); // <-- Utilisation du CRS explicite
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
            // Utilise toujours les coordonnées d'origine du GTFS (degrés)
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



    // --- Utilitaire pour parser l'en-tête CSV ---
    private static Map<String, Integer> parseHeader(String headerLine) {
        Map<String, Integer> colIdx = new HashMap<>();
        String[] headers = headerLine.split(",");
        for (int i = 0; i < headers.length; i++) {
            colIdx.put(headers[i], i);
        }
        return colIdx;
    }
}
