package gama.extension.GTFS;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.locationtech.jts.algorithm.ConvexHull;
import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.Geometry;
import org.locationtech.jts.geom.GeometryFactory;

import gama.core.util.GamaPair;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.annotations.precompiler.GamlAnnotations.example;
import gama.annotations.precompiler.GamlAnnotations.file;
import gama.annotations.precompiler.IConcept;
import gama.core.common.geometry.Envelope3D;
import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.GamaShape;
import gama.core.metamodel.shape.GamaShapeFactory;
import gama.core.runtime.IScope;
import gama.core.runtime.exceptions.GamaRuntimeException;
import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.IList;
import gama.core.util.IMap;
import gama.core.util.file.GamaFile;
import gama.gaml.types.IContainerType;
import gama.gaml.types.IType;
import gama.gaml.types.Types;
import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.opencsv.CSVParser;
import com.opencsv.CSVParserBuilder;
import com.opencsv.CSVReader;
import com.opencsv.CSVReaderBuilder;
import com.opencsv.exceptions.CsvValidationException;

/**
 * Reading and processing GTFS files in GAMA. This class reads multiple GTFS files
 * and creates TransportRoute, TransportTrip, and TransportStop objects.
 */
@file(
    name = "gtfs",
    extensions = { "txt" },
    buffer_type = IType.LIST,
    buffer_content = IType.STRING,
    buffer_index = IType.INT,
    concept = { IConcept.FILE },
    doc = @doc("GTFS files represent public transportation data in CSV format, typically with the '.txt' extension.")
)
public class GTFS_reader extends GamaFile<IList<String>, String> {

    // Required files for GTFS data
    private static final String[] REQUIRED_FILES = {
        "routes.txt", "trips.txt", "stop_times.txt", "stops.txt"
    };

    // Data structure to store GTFS files
    private IMap<String, List<String[]>> gtfsData;
    
    // New field to store header mappings for each file
    @SuppressWarnings("unchecked")
	private IMap<String, IMap<String, Integer>> headerMaps = GamaMapFactory.create(Types.STRING, Types.get(IMap.class));

    // Collections for objects created from GTFS files
    private IMap<String, TransportTrip> tripsMap;
    private IMap<String, TransportStop> stopsMap;
    private IMap<Integer, TransportShape> shapesMap;
    private IMap<String, TransportRoute> routesMap; 
    private IMap<Integer, Integer> shapeRouteTypeMap;
    private Map<String, Character> fileSeparators = new HashMap<>();
    
    /**
     * Constructor for reading GTFS files.
     *
     * @param scope    The simulation context in GAMA.
     * @param pathName The directory path containing GTFS files.
     * @throws GamaRuntimeException If an error occurs while loading the files.
     */
    @doc (
            value = "This constructor allows loading GTFS files from a specified directory.",
            examples = { @example (value = "GTFS_reader gtfs <- GTFS_reader(scope, \"path_to_gtfs_directory\");")})
    public GTFS_reader(final IScope scope, final String pathName) throws GamaRuntimeException {
        super(scope, pathName);
        
        // Debug: Print the GTFS path in the GAMA console
        if (scope != null && scope.getGui() != null) {
            scope.getGui().getConsole().informConsole("GTFS path used: "  + pathName, scope.getSimulation());
        } else {
            System.out.println("GTFS path used: " + pathName);  
        }

        // Load GTFS files
        System.out.println("Loading GTFS files...");
        loadGtfsFiles(scope);
        System.out.println("File loading completed.");
        
        // Create transport objects
        System.out.println("Creating transport objects...");
        createTransportObjects(scope);
        System.out.println("Transport object creation completed.");
       
    }

    public GTFS_reader(final String pathName) throws GamaRuntimeException {
        super(null, pathName);  // Pass 'null' for IScope as it is not needed here
        checkValidity(null);  // Pass 'null' if IScope is not necessary for this check
        loadGtfsFiles(null);
        createTransportObjects(null);
    }
    
    /**
     * Method to retrieve the list of stops (TransportStop) from stopsMap.
     * @return List of transport stops
     */
    public List<TransportStop> getStops() {
        List<TransportStop> stopList = new ArrayList<>(stopsMap.values());
        System.out.println("Number of created stops: " + stopList.size());
        return stopList;
    }
    
    /**
     * Method to retrieve the list of shape (TransportShape) from shapesMap.
     * @return List of transport shapes
     */   
    public List<TransportShape> getShapes() {
        return new ArrayList<>(shapesMap.values());
    }
    
    /**
     * Method to retrieve the list of trips (TransportTrip) from tripsMap.
     * @return List of transport trips
     */
    public List<TransportTrip> getTrips() {
    	return new ArrayList<>(tripsMap.values());
    }
    
    /**
     * Method to retrieve the list of routes (TransportRoute) from routesMap.
     * @return List of transport routes
     */
    public List<TransportRoute> getRoutes() {
        return new ArrayList<>(routesMap.values());
    }

    /**
     * Method to verify the directory's validity.
     *
     * @param scope    The simulation context in GAMA.
     * @throws GamaRuntimeException If the directory is invalid or does not contain required files.
     */
    @Override
    protected void checkValidity(final IScope scope) throws GamaRuntimeException {
        System.out.println("Starting directory validity check...");

        File folder = getFile(scope);

        if (!folder.exists() || !folder.isDirectory()) {
            throw GamaRuntimeException.error("The provided path for GTFS files is invalid. Ensure it is a directory containing .txt files.", scope);
        }

        Set<String> requiredFilesSet = new HashSet<>(Set.of(REQUIRED_FILES));
        File[] files = folder.listFiles();
        if (files != null) {
            for (File file : files) {
                String fileName = file.getName();
                if (fileName.endsWith(".txt")) {
                    requiredFilesSet.remove(fileName);
                }
            }
        }

        if (!requiredFilesSet.isEmpty()) {
            throw GamaRuntimeException.error("Missing GTFS files: " + requiredFilesSet, scope);
        }
        System.out.println("Directory validity check completed.");
    }

    /**
     * Loads GTFS files and verifies if all required files are present.
     */
    @SuppressWarnings("unchecked")
	private void loadGtfsFiles(final IScope scope) throws GamaRuntimeException {
        gtfsData = GamaMapFactory.create(Types.STRING, Types.LIST); // Use GamaMap for storing GTFS files
        headerMaps = GamaMapFactory.create(Types.STRING, Types.get(IMap.class));
        try {
            File folder = this.getFile(scope);
            File[] files = folder.listFiles();  // List of files in the folder
            if (files != null) {
                for (File file : files) {
                    if (file.isFile() && file.getName().endsWith(".txt")) {
                    	// 1. Détecte le séparateur
                    	char separator = detectSeparator(file);
                    	// 2. Mémorise le séparateur pour ce fichier
                    	fileSeparators.put(file.getName(), separator);
                    	// 3. Utilise OpenCSV avec le séparateur détecté
                    	Map<String, Integer> headerMap = new HashMap<>();
                    	List<String[]> fileContent = readCsvFileOpenCSV(file, headerMap);
                    	gtfsData.put(file.getName(), fileContent);
                    	IMap<String, Integer> headerIMap = GamaMapFactory.wrap(Types.STRING, Types.INT, headerMap);
                    	headerMaps.put(file.getName(), headerIMap);  
                        
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("Error while loading GTFS files: " + e.getMessage());
            throw GamaRuntimeException.create(e, scope);
        }

        System.out.println("All GTFS files have been loaded.");
        System.out.println("Headers loaded for files: " + headerMaps.keySet());
    }
    
    /**
     * Retrieves the header map for a given file.
     *
     * @param fileName The name of the file
     * @return The header map
     */
    private void createTransportObjectsWithShapes(
    	    IScope scope,
    	    IMap<String, Integer> routeTypeMap,
    	    IMap<Integer, String> shapeRouteMap,
    	    IMap<Integer, Integer> shapeRouteTypeMap
    	) {
    	    // 1. Création des TransportShape à partir de shapes.txt
    	    List<String[]> shapesData = gtfsData.get("shapes.txt");
    	    IMap<String, Integer> headerMap = headerMaps.get("shapes.txt");
    	    Integer shapeIdIndex = findColumnIndex(headerMap, "shape_id");
    	    Integer latIndex = findColumnIndex(headerMap, "shape_pt_lat");
    	    Integer lonIndex = findColumnIndex(headerMap, "shape_pt_lon");

    	    for (String[] fields : shapesData) {
    	        if (fields == null) continue;
    	        try {
    	            int shapeId = Integer.parseInt(fields[shapeIdIndex]);
    	            double lat = Double.parseDouble(fields[latIndex]);
    	            double lon = Double.parseDouble(fields[lonIndex]);
    	            TransportShape shape = shapesMap.get(shapeId);
    	            if (shape == null) {
    	                shape = new TransportShape(shapeId, "");
    	                shapesMap.put(shapeId, shape);
    	            }
    	            shape.addPoint(lat, lon, scope);
    	        } catch (Exception e) {
    	            System.err.println("[ERROR] Processing shape line: " + java.util.Arrays.toString(fields) + " -> " + e.getMessage());
    	        }
    	    }

    	    // 2. Création des trips (avec shapeId réel)
    	    List<String[]> tripsData = gtfsData.get("trips.txt");
    	    IMap<String, Integer> tripsHeaderMap = headerMaps.get("trips.txt");
    	    Integer routeIdIndex = findColumnIndex(tripsHeaderMap, "route_id");
    	    Integer tripIdIndex = findColumnIndex(tripsHeaderMap, "trip_id");
    	    Integer shapeIdIdx = findColumnIndex(tripsHeaderMap, "shape_id");

    	    for (String[] fields : tripsData) {
    	        if (fields == null) continue;
    	        try {
    	            String routeId = fields[routeIdIndex].trim().replace("\"", "").replace("'", "");
    	            String tripId = fields[tripIdIndex].trim().replace("\"", "").replace("'", "");
    	            int shapeId = -1;
    	            if (shapeIdIdx != null && fields.length > shapeIdIdx && !fields[shapeIdIdx].isEmpty()) {
    	                try { shapeId = Integer.parseInt(fields[shapeIdIdx]); } catch (Exception ignore) {}
    	            }
    	            TransportTrip trip = tripsMap.get(tripId);
    	            if (trip == null) {
    	                trip = new TransportTrip(routeId, "", tripId, 0, shapeId);
    	                tripsMap.put(tripId, trip);
    	            }
    	            // Set routeType
    	            if (routeTypeMap.containsKey(routeId)) {
    	                int routeType = routeTypeMap.get(routeId);
    	                trip.setRouteType(routeType);
    	            }
    	            // Lier shape et trip
    	            if (shapeId != -1 && shapesMap.containsKey(shapeId)) {
    	                shapeRouteTypeMap.put(shapeId, trip.getRouteType());
    	                shapeRouteMap.put(shapeId, routeId);
    	                shapesMap.get(shapeId).setTripId(tripId);
    	            }
    	        } catch (Exception e) {
    	            System.err.println("[ERROR] Invalid trip line in trips.txt: " + java.util.Arrays.toString(fields) + " -> " + e.getMessage());
    	        }
    	    }

    	    // 3. Assigner routeId/routeType aux shapes
    	    for (TransportShape shape : shapesMap.values()) {
    	        int shapeId = shape.getShapeId();
    	        if (shapeRouteMap.containsKey(shapeId)) {
    	            String routeId = shapeRouteMap.get(shapeId);
    	            shape.setRouteId(routeId);
    	        }
    	        if (shapeRouteTypeMap.containsKey(shapeId)) {
    	            shape.setRouteType(shapeRouteTypeMap.get(shapeId));
    	        }
    	    }

    	    // 4. Assigner routeType à tous les trips
    	    for (TransportTrip trip : tripsMap.values()) {
    	        if (trip.getRouteType() == -1 && routeTypeMap.containsKey(trip.getRouteId())) {
    	            trip.setRouteType(routeTypeMap.get(trip.getRouteId()));
    	        }
    	    }
    	}
    
    private void createTransportObjectsWithFakeShapes(
    	    IScope scope,
    	    IMap<String, Integer> routeTypeMap
    	) {
    	    // 1. Création des trips et shapes "fictifs"
    	    List<String[]> tripsData = gtfsData.get("trips.txt");
    	    IMap<String, Integer> tripsHeaderMap = headerMaps.get("trips.txt");
    	    Integer routeIdIndex = findColumnIndex(tripsHeaderMap, "route_id");
    	    Integer tripIdIndex = findColumnIndex(tripsHeaderMap, "trip_id");

    	    // On crée les trips, et pour chaque trip, on va créer un fake shape
    	    for (String[] fields : tripsData) {
    	        if (fields == null) continue;
    	        try {
    	            String routeId = fields[routeIdIndex].trim().replace("\"", "").replace("'", "");
    	            String tripId = fields[tripIdIndex].trim().replace("\"", "").replace("'", "");
    	            int fakeShapeId = Math.abs(tripId.hashCode()); // garanti unique

    	            // Crée le trip, avec shapeId = fakeShapeId
    	            TransportTrip trip = new TransportTrip(routeId, "", tripId, 0, fakeShapeId);
    	            tripsMap.put(tripId, trip);

    	            // Récupère la liste des stops pour ce trip
    	            List<String> stopIdsInOrder = new ArrayList<>();
    	            List<String[]> stopTimesData = gtfsData.get("stop_times.txt");
    	            IMap<String, Integer> stopTimesHeader = headerMaps.get("stop_times.txt");
    	            Integer tripIdIdxST = findColumnIndex(stopTimesHeader, "trip_id");
    	            Integer stopIdIdxST = findColumnIndex(stopTimesHeader, "stop_id");
    	            if (stopTimesData != null && tripIdIdxST != null && stopIdIdxST != null) {
    	                for (String[] stFields : stopTimesData) {
    	                    if (stFields == null) continue;
    	                    String tripIdST = stFields[tripIdIdxST].trim().replace("\"", "").replace("'", "");
    	                    if (tripIdST.equals(tripId)) {
    	                        String stopId = stFields[stopIdIdxST].trim().replace("\"", "").replace("'", "");
    	                        stopIdsInOrder.add(stopId);
    	                    }
    	                }
    	            }
    	            // On construit la fake polyline avec les coordonnées des stops
    	            List<GamaPoint> shapePoints = new ArrayList<>();
    	            for (String stopId : stopIdsInOrder) {
    	                TransportStop stop = stopsMap.get(stopId);
    	                if (stop != null) {
    	                    shapePoints.add(new GamaPoint(stop.getStopLat(), stop.getStopLon()));
    	                }
    	            }
    	            // Crée le fake shape seulement s'il y a au moins 2 points
    	            if (shapePoints.size() > 1) {
    	                TransportShape fakeShape = new TransportShape(fakeShapeId, routeId);
    	                for (GamaPoint pt : shapePoints) fakeShape.addPoint(pt.getX(), pt.getY(), scope);
    	                // On peut setter la routeType à ce fakeShape
    	                if (routeTypeMap.containsKey(routeId)) fakeShape.setRouteType(routeTypeMap.get(routeId));
    	                // TripId pour référence
    	                fakeShape.setTripId(tripId);
    	                shapesMap.put(fakeShapeId, fakeShape);
    	            }

    	            // Set le routeType du trip
    	            if (routeTypeMap.containsKey(routeId)) {
    	                trip.setRouteType(routeTypeMap.get(routeId));
    	            }
    	        } catch (Exception e) {
    	            
    	        }
    	    }
    	}


    @SuppressWarnings("unchecked")
    private void createTransportObjects(IScope scope) {
        System.out.println("Starting transport object creation...");

        // Initialisation des maps globales
        routesMap = GamaMapFactory.create(Types.STRING, Types.get(TransportRoute.class)); 
        stopsMap = GamaMapFactory.create(Types.STRING, Types.get(TransportStop.class));   
        tripsMap = GamaMapFactory.create(Types.STRING, Types.get(TransportTrip.class));     
        shapesMap = GamaMapFactory.create(Types.INT, Types.get(TransportShape.class));	
        shapeRouteTypeMap = GamaMapFactory.create();

        // Map pour lier shapeId <-> routeId, shapeId <-> routeType
        IMap<Integer, String> shapeRouteMap = GamaMapFactory.create(Types.INT, Types.STRING); 
        IMap<Integer, Integer> shapeRouteTypeMapLocal = GamaMapFactory.create(Types.INT, Types.INT);

        // 1. Lecture des routeType par routeId (commune)
        IMap<String, Integer> routeTypeMap = GamaMapFactory.create(Types.STRING, Types.INT);
        List<String[]> routesData = gtfsData.get("routes.txt");
        IMap<String, Integer> routesHeader = headerMaps.get("routes.txt");

        if (routesData != null && routesHeader != null) {
            Integer routeIdIndex = findColumnIndex(routesHeader, "route_id");
            Integer routeTypeIndex = findColumnIndex(routesHeader, "route_type");
            if (routeIdIndex == null || routeTypeIndex == null) {
                throw new RuntimeException("route_id or route_type column not found in routes.txt!");
            }
            for (String[] fields : routesData) {
                if (fields == null) continue;
                try {
                    String routeId = fields[routeIdIndex].trim().replace("\"", "").replace("'", "");
                    int routeType = Integer.parseInt(fields[routeTypeIndex]);
                    routeTypeMap.put(routeId, routeType);
                } catch (Exception e) {
                    System.err.println("[ERROR] Invalid routeType in routes.txt: " + java.util.Arrays.toString(fields) + " -> " + e.getMessage());
                }
            }
        }

        // 2. Collecte des stop_ids utilisés (commun)
        Set<String> usedStopIds = new HashSet<>();
        List<String[]> stopTimesData = gtfsData.get("stop_times.txt");
        IMap<String, Integer> stopTimesHeader = headerMaps.get("stop_times.txt");

        if (stopTimesData != null && stopTimesHeader != null && stopTimesHeader.containsKey("stop_id")) {
            Integer stopIdIndex = stopTimesHeader.get("stop_id");
            if (stopIdIndex == null) throw new RuntimeException("stop_id column not found in stop_times.txt!");
            for (String[] fields : stopTimesData) {
                if (fields == null || fields.length <= stopIdIndex) continue;
                usedStopIds.add(fields[stopIdIndex].trim().replace("\"", "").replace("'", ""));
            }
        }

        // 3. Création des stops (commun)
        List<String[]> stopsData = gtfsData.get("stops.txt");
        IMap<String, Integer> headerIMap = headerMaps.get("stops.txt");

        if (stopsData != null && headerIMap != null) {
            Integer stopIdIndex = findColumnIndex(headerIMap, "stop_id");
            Integer stopNameIndex = findColumnIndex(headerIMap, "stop_name");
            Integer stopLatIndex = findColumnIndex(headerIMap, "stop_lat");
            Integer stopLonIndex = findColumnIndex(headerIMap, "stop_lon");

            if (stopIdIndex == null || stopNameIndex == null || stopLatIndex == null || stopLonIndex == null) {
                throw new RuntimeException("stop_id, stop_name, stop_lat or stop_lon column not found in stops.txt!");
            }

            for (String[] fields : stopsData) {
                if (fields == null) continue;
                try {
                    String stopId = fields[stopIdIndex].trim().replace("\"", "").replace("'", ""); 
                    if (!usedStopIds.contains(stopId)) continue;

                    String stopName = fields[stopNameIndex];
                    double stopLat = Double.parseDouble(fields[stopLatIndex]);
                    double stopLon = Double.parseDouble(fields[stopLonIndex]);

                    TransportStop stop = new TransportStop(stopId, stopName, stopLat, stopLon, scope);
                    stopsMap.put(stopId, stop);
                } catch (Exception e) {
                    System.err.println("[ERROR] Processing stop line: " + java.util.Arrays.toString(fields) + " -> " + e.getMessage());
                }
            }
        }
        System.out.println("Finished creating TransportStop objects.");

        // 4. Teste la présence de shapes.txt
        List<String[]> shapesData = gtfsData.get("shapes.txt");
        IMap<String, Integer> headerMap = headerMaps.get("shapes.txt");
        boolean shapesTxtExists = (shapesData != null && headerMap != null && !shapesData.isEmpty());

        // 5. Appelle la bonne méthode selon shapes.txt
        if (shapesTxtExists) {
            System.out.println("[INFO] shapes.txt found. Using standard GTFS shapes pipeline.");
            createTransportObjectsWithShapes(scope, routeTypeMap, shapeRouteMap, shapeRouteTypeMapLocal);
            // Fusionne dans la map globale si besoin
            shapeRouteTypeMap.putAll(shapeRouteTypeMapLocal);
        } else {
            System.out.println("[INFO] shapes.txt NOT found. Using fake shapes fallback.");
            createTransportObjectsWithFakeShapes(scope, routeTypeMap);
        }

        // 6. Affecte le routeType à tous les trips qui n'ont pas été remplis (commune)
        for (TransportTrip trip : tripsMap.values()) {
            if (trip.getRouteType() == -1 && routeTypeMap.containsKey(trip.getRouteId())) {
                trip.setRouteType(routeTypeMap.get(trip.getRouteId()));
            }
        }

        // 7. Résumé et computeDepartureInfo (communs)
        System.out.println("------ Résumé chargement objets GTFS ------");
        System.out.println("Nombre de TransportTrip (tripsMap)         : " + tripsMap.size());
        System.out.println("Nombre de TransportStop (stopsMap)         : " + stopsMap.size());
        System.out.println("Nombre de TransportShape (shapesMap)       : " + shapesMap.size());
        System.out.println("Nombre de shapeRouteTypeMap                : " + shapeRouteTypeMap.size());
        System.out.println("-------------------------------------------");

        System.out.println("[INFO] Finished assigning routeType to TransportShape and TransportTrip.");
        System.out.println("[INFO] Calling computeDepartureInfo...");
        computeDepartureInfo(scope);
        
        System.out.println("[INFO] Début de la propagation finale des routeType aux stops...");
        int propagated = 0;
        for (TransportTrip trip : tripsMap.values()) {
            int routeType = trip.getRouteType();
            if (routeType == -1) {
                System.out.println("[DEBUG] Trip " + trip.getTripId() + " a routeType=-1 => ignoré");
                continue;
            }
            List<String> orderedStops = trip.getStopsInOrder();
            if (orderedStops == null || orderedStops.isEmpty()) {
                System.out.println("[DEBUG] Trip " + trip.getTripId() + " a stopsInOrder vide");
                continue;
            }

            for (String stopId : orderedStops) {
                TransportStop stop = stopsMap.get(stopId);
                if (stop != null && stop.getRouteType() == -1) {
                    stop.setRouteType(routeType);
                    propagated++;
                    System.out.println("[INFO] ✅ Propagation : stop " + stopId + " reçoit routeType " + routeType + " depuis trip " + trip.getTripId());
                }
            }
        }
        System.out.println("✅ Tous les stops ont reçu leur routeType à partir des trips complets. (nouveaux assignés : " + propagated + ")");
        System.out.println("[INFO] computeDepartureInfo completed.");

        System.out.println("[INFO] Réinitialisation des routeType à -1 pour tous les stops...");
        for (TransportStop stop : stopsMap.values()) {
            stop.setRouteType(-1);
        }

        System.out.println("[INFO] Début de la propagation finale des routeType aux stops...");
        int counter = 0;
        for (TransportTrip trip : tripsMap.values()) {
            int routeType = trip.getRouteType();
            if (routeType == -1) continue;

            for (String stopId : trip.getStopsInOrder()) {
                TransportStop stop = stopsMap.get(stopId);
                if (stop != null && stop.getRouteType() == -1) {
                    stop.setRouteType(routeType);
                    counter++;
                }
            }
        }
        System.out.println("✅ Tous les stops ont reçu leur routeType à partir des trips complets. (nouveaux assignés : " + counter + ")");

    }



    private char detectSeparator(File file) throws IOException {
        try (BufferedReader br = new BufferedReader(new FileReader(file))) {
            String line;
            while ((line = br.readLine()) != null) {
                // Ignore les lignes vides
                if (line.trim().isEmpty()) continue;

                // Compte virgules/points-virgules hors guillemets
                int commaCount = 0, semicolonCount = 0;
                boolean inQuotes = false;
                for (char c : line.toCharArray()) {
                    if (c == '"') inQuotes = !inQuotes;
                    if (!inQuotes) {
                        if (c == ',') commaCount++;
                        if (c == ';') semicolonCount++;
                    }
                }
                if (semicolonCount > commaCount) return ';';
                else return ','; // Virgule par défaut
            }
        }
        // Par défaut, virgule
        return ',';
    }

    
    public static String[] parseCsvLine(String line, char separator) {
        try {
            CSVParser parser = new CSVParserBuilder().withSeparator(separator).build();
            return parser.parseLine(line);
        } catch (Exception e) {
            System.err.println("[ERROR] CSV parsing failed: " + line);
            return null;
        }
    }

    /**
     * Reads a CSV file 
     */
    private List<String[]> readCsvFileOpenCSV(File file, Map<String, Integer> headerMap) throws IOException, CsvValidationException {
        List<String[]> content = new ArrayList<>();
        if (!file.isFile()) {
            throw new IOException(file.getAbsolutePath() + " is not a valid file.");
        }

        char separator = detectSeparator(file);

        try (CSVReader reader = new CSVReaderBuilder(new FileReader(file))
                                    .withSkipLines(0)
                                    .withCSVParser(new CSVParserBuilder().withSeparator(separator).build())
                                    .build()) {
            // Lis et nettoie le header
            String[] headers = reader.readNext();
            while (headers != null && headers.length == 1 && headers[0].trim().isEmpty()) {
                headers = reader.readNext();
            }
            if (headers != null) {
                for (int i = 0; i < headers.length; i++) {
                    String col = headers[i].trim().replace("\uFEFF", "").toLowerCase();
                    headerMap.put(col, i);
                }
            }
            String[] line;
            while ((line = reader.readNext()) != null) {
                // Complète les champs manquants (à droite)
                if (line.length < headerMap.size()) {
                    String[] newLine = new String[headerMap.size()];
                    System.arraycopy(line, 0, newLine, 0, line.length);
                    for (int i = line.length; i < headerMap.size(); i++) {
                        newLine[i] = "";
                    }
                    line = newLine;
                }
                // Ignore les lignes totalement vides
                boolean isEmpty = true;
                for (String field : line) {
                    if (field != null && !field.trim().isEmpty()) {
                        isEmpty = false;
                        break;
                    }
                }
                if (isEmpty) continue;
                content.add(line); // Ajoute le tableau de champs
            }
        }
        return content;
    }




    /**
     * Trouve l’index d’une colonne parmi plusieurs possibilités dans le headerMap.
     * @param headerMap La map colonne → index.
     * @param possibleNames Liste de noms possibles (ex: "stop_id", "stopid"...).
     * @return L’index si trouvé, sinon null.
     */
    private Integer findColumnIndex(Map<String, Integer> headerMap, String... possibleNames) {
        if (headerMap == null) return null;
        for (String target : possibleNames) {
            for (String col : headerMap.keySet()) {
                if (col.equalsIgnoreCase(target.trim())) return headerMap.get(col);
            }
        }
        return null;
    }

    
    @Override
    protected void fillBuffer(final IScope scope) throws GamaRuntimeException {
    	System.out.println("Filling buffer...");
        if (gtfsData == null) {
        	System.out.println("gtfsData is null, loading GTFS files...");
            loadGtfsFiles(scope);
            System.out.println("Finished loading GTFS files.");
        }else
        	 System.out.println("gtfsData is already initialized.");
    
    }

    @Override
    public IList<String> getAttributes(final IScope scope) {
    	System.out.println("Retrieving GTFS data attributes...");
    	if (gtfsData != null) {
            Set<String> keySet = gtfsData.keySet();
            System.out.println("Attributes retrieved: " + keySet);
            return GamaListFactory.createWithoutCasting(Types.STRING, keySet.toArray(new String[0]));
        } else {
            System.out.println("gtfsData is null, no attributes to retrieve.");
            return GamaListFactory.createWithoutCasting(Types.STRING);
        }
    }

	@SuppressWarnings("unchecked")
	@Override
    public IContainerType<IList<String>> getGamlType() {
    	System.out.println("Returning GAML type for GTFS file.");
        return Types.FILE.of(Types.STRING, Types.STRING);
    }

    @Override
    public Envelope3D computeEnvelope(final IScope scope) {
        // Provide a default implementation or return an empty envelope
        return Envelope3D.EMPTY;
    }

    public List<TransportTrip> getActiveTripsForDate(IScope scope, LocalDate date) {
        Set<String> activeTripIds = getActiveTripIdsForDate(scope, date);
        List<TransportTrip> activeTrips = new ArrayList<>();
        for (String tripId : activeTripIds) {
            TransportTrip trip = tripsMap.get(tripId);
            if (trip != null) activeTrips.add(trip);
        }
        return activeTrips;
    }
    
    public void computeDepartureInfo(IScope scope) {
        System.out.println("Starting computeDepartureInfo...");

        // 1. Lecture de la date de simulation (aucune modif)
        LocalDate simulationDate = LocalDate.now();
        try {
            Object startingDateObj = scope.getGlobalVarValue("starting_date");
            System.out.println("DEBUG - starting_date from GAMA = " + startingDateObj + " (class: " + (startingDateObj != null ? startingDateObj.getClass() : "null") + ")");
            if (startingDateObj != null) {
                if (startingDateObj instanceof gama.core.util.GamaDate) {
                    gama.core.util.GamaDate gd = (gama.core.util.GamaDate) startingDateObj;
                    simulationDate = gd.getLocalDateTime().toLocalDate();
                } else if (startingDateObj instanceof java.util.Date) {
                    java.util.Date d = (java.util.Date) startingDateObj;
                    simulationDate = d.toInstant().atZone(java.time.ZoneId.systemDefault()).toLocalDate();
                } else if (startingDateObj instanceof String) {
                    String val = (String) startingDateObj;
                    try {
                        simulationDate = java.time.LocalDateTime.parse(val, java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")).toLocalDate();
                    } catch (Exception ex1) {
                        try {
                            simulationDate = LocalDate.parse(val.substring(0, 10));
                        } catch (Exception ex2) {
                            System.err.println("[ERROR] Impossible de parser starting_date string: '" + val + "' : " + ex2.getMessage());
                        }
                    }
                } else {
                    System.err.println("[ERROR] Unhandled type for starting_date: " + startingDateObj.getClass().getName());
                }
            }
            System.out.println("DEBUG - simulationDate used in Java = " + simulationDate);
        } catch (Exception e) {
            System.err.println("[ERROR] Failed to read starting_date from GAMA scope: " + e.getMessage());
        }

        // 2. Extraction des trips actifs
        Set<String> activeTripIds = getActiveTripIdsForDate(scope, simulationDate);
        System.out.println("activeTripIds.size() = " + activeTripIds.size());
        int nbBusTrips = 0;
        for (String tripId : activeTripIds) {
            TransportTrip trip = tripsMap.get(tripId);
            if (trip != null && trip.getRouteType() == 3) {
                nbBusTrips++;
            }
        }
        System.out.println("Nombre de trips BUS actifs pour la date " + simulationDate + " : " + nbBusTrips);

        if (activeTripIds.isEmpty()) {
            System.err.println("[WARNING] No active trips found for simulation date: " + simulationDate);
        } else if (activeTripIds.size() < 10) {
            System.out.println("activeTripIds = " + activeTripIds); // debug
        }

        // 3. Sécuriser la lecture des colonnes
        List<String[]> stopTimesData = (List<String[]>) gtfsData.get("stop_times.txt");
        IMap<String, Integer> stopTimesHeader = headerMaps.get("stop_times.txt");
        if (stopTimesData == null || stopTimesHeader == null) {
            System.err.println("[ERROR] stop_times.txt data or headers are missing!");
            return;
        }
        Integer tripIdIndex = findColumnIndex(stopTimesHeader, "trip_id");
        Integer stopIdIndex = findColumnIndex(stopTimesHeader, "stop_id");
        Integer departureTimeIndex = findColumnIndex(stopTimesHeader, "departure_time");
        if (tripIdIndex == null || stopIdIndex == null || departureTimeIndex == null) {
            System.err.println("[ERROR] Required columns missing in stop_times.txt!");
            return;
        }

        // 4. Remplissage séquentiel des trips et stops
        int totalAdded = 0;
        int totalSkipped = 0;
        int totalMissingTrip = 0;

        for (String[] fields : stopTimesData) {
            if (fields == null || fields.length <= Math.max(tripIdIndex, Math.max(stopIdIndex, departureTimeIndex))) {
                System.out.println("[SKIP] Ligne ignorée (champ manquant), taille=" + fields.length);
                totalSkipped++;
                continue;
            }

            try {
                // Nettoyage de trip_id et stop_id
                String tripId = fields[tripIdIndex].trim().replace("\"", "").replace("'", "");
                String stopId = fields[stopIdIndex].trim().replace("\"", "").replace("'", "");
                String departureTime = fields[departureTimeIndex];

                // Vérification existence du trip
                TransportTrip trip = tripsMap.get(tripId);
                if (trip == null) {
                    System.err.println("[WARNING] tripId \"" + tripId + "\" non trouvé dans tripsMap.");
                    totalMissingTrip++;
                    continue;
                }

                // Ajout du stop dans le trip
                trip.addStop(stopId);
                trip.addStopDetail(stopId, departureTime, 0.0);
                totalAdded++;

                // Récupération ou création du stop
                TransportStop stop = stopsMap.get(stopId);
                if (stop != null) {
                    int tripRouteType = trip.getRouteType();
                    if (tripRouteType != -1 && stop.getRouteType() == -1) {
                        stop.setRouteType(tripRouteType);
                    }
                    stop.addTripShapePair(tripId, trip.getShapeId());
                }

            } catch (Exception e) {
                System.err.println("[ERROR] Échec traitement ligne : " + Arrays.toString(fields) + " → " + e.getMessage());
            }
        }

        System.out.println("🔎 Résumé computeDepartureInfo():");
        System.out.println("   → Stops ajoutés dans trips : " + totalAdded);
        System.out.println("   → Lignes ignorées (incomplètes) : " + totalSkipped);
        System.out.println("   → tripId non trouvés dans tripsMap : " + totalMissingTrip);
        // 5. Création des departureTripsInfo (infos de départ par stop)
        IMap<String, IList<GamaPair<String, String>>> departureTripsInfo = GamaMapFactory.create(Types.STRING, Types.LIST);
        for (String tripId : activeTripIds) {
            TransportTrip trip = tripsMap.get(tripId);
            if (trip == null) continue;
            IList<String> stopsInOrder = trip.getStopsInOrder();
            IList<IMap<String, Object>> stopDetails = trip.getStopDetails();
            IList<GamaPair<String, String>> stopPairs = GamaListFactory.create(Types.PAIR);

            if (stopsInOrder.isEmpty() || stopDetails.size() != stopsInOrder.size()) continue;

            for (int i = 0; i < stopsInOrder.size(); i++) {
                String stopId = stopsInOrder.get(i);
                String departureTime = stopDetails.get(i).get("departureTime").toString();
                String departureInSeconds = convertTimeToSeconds(departureTime);
                stopPairs.add(new GamaPair<>(stopId, departureInSeconds, Types.STRING, Types.STRING));
            }
            departureTripsInfo.put(tripId, stopPairs);
        }

        // 6. Filtrage et classement des trips par stop de départ (dédoublonnage + tri)
        Map<String, List<String>> stopToTripIds = new HashMap<>();
        Set<String> seenTripSignatures = new HashSet<>();
        for (String tripId : departureTripsInfo.keySet()) {
            IList<GamaPair<String, String>> stopPairs = departureTripsInfo.get(tripId);
            if (stopPairs == null || stopPairs.isEmpty()) continue;

            String firstStopId = stopPairs.get(0).key;
            String departureTime = stopPairs.get(0).value;
            StringBuilder stopSequence = new StringBuilder();
            for (GamaPair<String, String> pair : stopPairs) stopSequence.append(pair.key).append(";");
            String signature = firstStopId + "_" + departureTime + "_" + stopSequence;

            if (seenTripSignatures.contains(signature)) continue;
            seenTripSignatures.add(signature);
            stopToTripIds.computeIfAbsent(firstStopId, k -> new ArrayList<>()).add(tripId);
        }

        // 7. Affectation dans chaque stop + tri + comptage
        for (Map.Entry<String, List<String>> entry : stopToTripIds.entrySet()) {
            String stopId = entry.getKey();
            List<String> tripIds = entry.getValue();

            tripIds.sort((id1, id2) -> {
                String t1 = departureTripsInfo.get(id1).get(0).value;
                String t2 = departureTripsInfo.get(id2).get(0).value;
                return Integer.compare(Integer.parseInt(t1), Integer.parseInt(t2));
            });

            TransportStop stop = stopsMap.get(stopId);
            if (stop == null) continue;
            stop.ensureDepartureTripsInfo();
            for (String tripId : tripIds) {
                IList<GamaPair<String, String>> pairs = departureTripsInfo.get(tripId);
                stop.addStopPairs(tripId, pairs);
            }
            stop.setTripNumber(stop.getDepartureTripsInfo().size());
        }

        // 8. Résumé final
        int nbStopsAvecTrips = 0;
        for (TransportStop stop : stopsMap.values()) {
            if (stop.getDepartureTripsInfo() != null && !stop.getDepartureTripsInfo().isEmpty()) nbStopsAvecTrips++;
        }
        System.out.println("Nombre de stops avec departureTripsInfo non vide : " + nbStopsAvecTrips);
        System.out.println("Nombre de trips au total dans tripsMap : " + tripsMap.size());
        System.out.println("✅ computeDepartureInfo completed successfully.");
    }


    private Set<String> getActiveTripIdsForDate(IScope scope, LocalDate date) {
        Set<String> validTripIds = new HashSet<>();
        Map<String, String> tripIdToServiceId = new HashMap<>();

        List<String[]> tripsData = (List<String[]>) gtfsData.get("trips.txt");
        IMap<String, Integer> tripsHeader = headerMaps.get("trips.txt");

        if (tripsData == null || tripsHeader == null) {
            System.err.println("[ERROR] trips.txt data or headers are missing!");
            return validTripIds;
        }

        Integer tripIdIdx = findColumnIndex(tripsHeader, "trip_id");
        Integer serviceIdIdx = findColumnIndex(tripsHeader, "service_id");
        if (tripIdIdx == null || serviceIdIdx == null) {
            System.err.println("[ERROR] trip_id or service_id column missing in trips.txt!");
            return validTripIds;
        }

        for (String[] fields : tripsData) {
            // Ignore les lignes vides ou mal formées
            if (fields.length > Math.max(tripIdIdx, serviceIdIdx)) {
                tripIdToServiceId.put(fields[tripIdIdx].trim().replace("\"", ""), fields[serviceIdIdx].trim().replace("\"", ""));
            }
        }

        List<String[]> calendarData = (List<String[]>) gtfsData.get("calendar.txt");
        List<String[]> calendarDatesData = (List<String[]>) gtfsData.get("calendar_dates.txt");
        boolean hasCalendar = (calendarData != null && !calendarData.isEmpty());
        boolean hasCalendarDates = (calendarDatesData != null && !calendarDatesData.isEmpty());

        Set<String> activeServiceIds = new HashSet<>();
        java.time.format.DateTimeFormatter formatter = java.time.format.DateTimeFormatter.ofPattern("yyyyMMdd");
        String dayOfWeek = date.getDayOfWeek().toString().toLowerCase();

        if (hasCalendar) {
            IMap<String, Integer> calendarHeader = headerMaps.get("calendar.txt");
            if (calendarHeader == null) {
                System.err.println("[ERROR] calendar.txt headers missing!");
            } else {
                try {
                    Integer serviceIdIdxCal = findColumnIndex(calendarHeader, "service_id");
                    Integer startIdx = findColumnIndex(calendarHeader, "start_date");
                    Integer endIdx = findColumnIndex(calendarHeader, "end_date");
                    Integer dayIdx = findColumnIndex(calendarHeader, dayOfWeek);
                    if (serviceIdIdxCal == null || startIdx == null || endIdx == null || dayIdx == null) {
                        System.err.println("[ERROR] Some required columns are missing in calendar.txt!");
                    } else {
                        for (String[] fields : calendarData) {
                            if (fields.length <= Math.max(Math.max(serviceIdIdxCal, startIdx), Math.max(endIdx, dayIdx))) continue;
                            String serviceId = fields[serviceIdIdxCal].trim().replace("\"", "");
                            LocalDate start = LocalDate.parse(fields[startIdx], formatter);
                            LocalDate end = LocalDate.parse(fields[endIdx], formatter);
                            boolean runsToday = fields[dayIdx].equals("1") && !date.isBefore(start) && !date.isAfter(end);
                            if (runsToday) activeServiceIds.add(serviceId);
                        }
                    }
                } catch (Exception e) {
                    System.err.println("[ERROR] Processing calendar.txt failed: " + e.getMessage());
                }
            }
        }

        if (hasCalendarDates) {
            IMap<String, Integer> calDatesHeader = headerMaps.get("calendar_dates.txt");
            if (calDatesHeader == null) {
                System.err.println("[ERROR] calendar_dates.txt headers missing!");
            } else {
                try {
                    Integer serviceIdIdxCal = findColumnIndex(calDatesHeader, "service_id");
                    Integer dateIdx = findColumnIndex(calDatesHeader, "date");
                    Integer exceptionTypeIdx = findColumnIndex(calDatesHeader, "exception_type");
                    if (serviceIdIdxCal == null || dateIdx == null || exceptionTypeIdx == null) {
                        System.err.println("[ERROR] Some required columns are missing in calendar_dates.txt!");
                    } else {
                        for (String[] fields : calendarDatesData) {
                            if (fields.length <= Math.max(Math.max(serviceIdIdxCal, dateIdx), exceptionTypeIdx)) continue;
                            String serviceId = fields[serviceIdIdxCal].trim().replace("\"", "");
                            LocalDate exceptionDate = LocalDate.parse(fields[dateIdx], formatter);
                            int exceptionType = Integer.parseInt(fields[exceptionTypeIdx]);
                            if (exceptionDate.equals(date)) {
                                if (exceptionType == 1) activeServiceIds.add(serviceId);
                                if (exceptionType == 2) activeServiceIds.remove(serviceId);
                            }
                        }
                    }
                } catch (Exception e) {
                    System.err.println("[ERROR] Processing calendar_dates.txt failed: " + e.getMessage());
                }
            }
        }

        for (Map.Entry<String, String> e : tripIdToServiceId.entrySet()) {
            if (activeServiceIds.contains(e.getValue())) validTripIds.add(e.getKey());
        }

        if (validTripIds.isEmpty()) {
            // Cherche un jour équivalent dans GTFS
            LocalDate altDate = findFirstDateWithSameWeekDay(date);
            if (altDate != null && !altDate.equals(date)) {
                System.out.println("[INFO] No trips for " + date + ", fallback to first same weekday in GTFS: " + altDate);
                // Appel récursif avec la nouvelle date (évite boucle infinie avec un flag si besoin)
                return getActiveTripIdsForDate(scope, altDate);
            } else {
                System.err.println("[WARNING] No matching weekday found in GTFS. Fallback: all trips.");
                validTripIds.addAll(tripIdToServiceId.keySet());
            }
        }


        return validTripIds;
    }
    
    private LocalDate findFirstDateWithSameWeekDay(LocalDate wantedDate) {
        List<LocalDate> allDates = new ArrayList<>();
        java.time.format.DateTimeFormatter formatter = java.time.format.DateTimeFormatter.ofPattern("yyyyMMdd");
        
        // calendar.txt
        List<String[]> calendarData = (List<String[]>) gtfsData.get("calendar.txt");
        if (calendarData != null && !calendarData.isEmpty()) {
            IMap<String, Integer> header = headerMaps.get("calendar.txt");
            if (header != null) {
                Integer startIdx = findColumnIndex(header, "start_date");
                Integer endIdx = findColumnIndex(header, "end_date");
                if (startIdx != null && endIdx != null) {
                    for (String[] fields : calendarData) {
                        if (fields.length > endIdx) {
                            LocalDate start = LocalDate.parse(fields[startIdx], formatter);
                            LocalDate end = LocalDate.parse(fields[endIdx], formatter);
                            for (LocalDate d = start; !d.isAfter(end); d = d.plusDays(1)) {
                                allDates.add(d);
                            }
                        }
                    }
                }
            }
        }
        // calendar_dates.txt
        List<String[]> calendarDates = (List<String[]>) gtfsData.get("calendar_dates.txt");
        if (calendarDates != null && !calendarDates.isEmpty()) {
            IMap<String, Integer> header = headerMaps.get("calendar_dates.txt");
            if (header != null) {
                Integer dateIdx = findColumnIndex(header, "date");
                if (dateIdx != null) {
                    for (String[] fields : calendarDates) {
                        if (fields.length > dateIdx) {
                            LocalDate d = LocalDate.parse(fields[dateIdx], formatter);
                            allDates.add(d);
                        }
                    }
                }
            }
        }
        // Recherche du premier jour avec le même dayOfWeek
        LocalDate firstMatch = null;
        for (LocalDate d : allDates) {
            if (d.getDayOfWeek().equals(wantedDate.getDayOfWeek())) {
                if (firstMatch == null || d.isBefore(firstMatch)) firstMatch = d;
            }
        }
        return firstMatch;
    }

    
    public java.time.LocalDate getStartingDate() {
        java.time.LocalDate minDate = null;
        java.time.format.DateTimeFormatter formatter = java.time.format.DateTimeFormatter.ofPattern("yyyyMMdd");

        // calendar.txt
        List<String[]> calendarData = (List<String[]>) gtfsData.get("calendar.txt");
        if (calendarData != null && !calendarData.isEmpty()) {
            IMap<String, Integer> header = headerMaps.get("calendar.txt");
            if (header != null) {
                Integer startIdx = findColumnIndex(header, "start_date");
                if (startIdx != null) {
                    for (String[] fields : calendarData) {
                        if (fields.length > startIdx) {
                            java.time.LocalDate d = java.time.LocalDate.parse(fields[startIdx], formatter);
                            if (minDate == null || d.isBefore(minDate)) minDate = d;
                        }
                    }
                }
            }
        }

        // calendar_dates.txt
        List<String[]> calendarDates = (List<String[]>) gtfsData.get("calendar_dates.txt");
        if (calendarDates != null && !calendarDates.isEmpty()) {
            IMap<String, Integer> header = headerMaps.get("calendar_dates.txt");
            if (header != null) {
                Integer dateIdx = findColumnIndex(header, "date");
                if (dateIdx != null) {
                    for (String[] fields : calendarDates) {
                        if (fields.length > dateIdx) {
                            java.time.LocalDate d = java.time.LocalDate.parse(fields[dateIdx], formatter);
                            if (minDate == null || d.isBefore(minDate)) minDate = d;
                        }
                    }
                }
            }
        }
        return minDate;
    }


    public java.time.LocalDate getEndingDate() {
        java.time.LocalDate maxDate = null;
        java.time.format.DateTimeFormatter formatter = java.time.format.DateTimeFormatter.ofPattern("yyyyMMdd");

        // calendar.txt
        List<String[]> calendarData = (List<String[]>) gtfsData.get("calendar.txt");
        if (calendarData != null && !calendarData.isEmpty()) {
            IMap<String, Integer> header = headerMaps.get("calendar.txt");
            if (header != null) {
                Integer endIdx = findColumnIndex(header, "end_date");
                if (endIdx != null) {
                    for (String[] fields : calendarData) {
                        if (fields.length > endIdx) {
                            java.time.LocalDate d = java.time.LocalDate.parse(fields[endIdx], formatter);
                            if (maxDate == null || d.isAfter(maxDate)) maxDate = d;
                        }
                    }
                }
            }
        }
        // calendar_dates.txt
        List<String[]> calendarDates = (List<String[]>) gtfsData.get("calendar_dates.txt");
        if (calendarDates != null && !calendarDates.isEmpty()) {
            IMap<String, Integer> header = headerMaps.get("calendar_dates.txt");
            if (header != null) {
                Integer dateIdx = findColumnIndex(header, "date");
                if (dateIdx != null) {
                    for (String[] fields : calendarDates) {
                        if (fields.length > dateIdx) {
                            java.time.LocalDate d = java.time.LocalDate.parse(fields[dateIdx], formatter);
                            if (maxDate == null || d.isAfter(maxDate)) maxDate = d;
                        }
                    }
                }
            }
        }
        return maxDate;
    }

    

    
    // Method to convert departureTime of stops into seconds
    private String convertTimeToSeconds(String timeStr) {
        try {
            String[] parts = timeStr.split(":");
            int hours = Integer.parseInt(parts[0]);
            int minutes = Integer.parseInt(parts[1]);
            int seconds = Integer.parseInt(parts[2]);
            int totalSeconds = (hours * 3600 + minutes * 60 + seconds);
            return String.valueOf(totalSeconds);
        } catch (Exception e) {
            System.err.println("[ERROR] Failed to convert time: " + timeStr + " -> " + e.getMessage());
            return "0";  // fallback
        }
    }
    
   
}