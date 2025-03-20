package gama.extension.GTFS;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import gama.core.util.GamaPair;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.annotations.precompiler.GamlAnnotations.example;
import gama.annotations.precompiler.GamlAnnotations.file;
import gama.annotations.precompiler.IConcept;
import gama.core.common.geometry.Envelope3D;
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
        "agency.txt", "routes.txt", "trips.txt", "calendar.txt", "stop_times.txt", "stops.txt"
    };

    // Data structure to store GTFS files
    private IMap<String, IList<String>> gtfsData;
    
    // New field to store header mappings for each file
    @SuppressWarnings("unchecked")
	private IMap<String, IMap<String, Integer>> headerMaps = GamaMapFactory.create(Types.STRING, Types.get(IMap.class));

    // Collections for objects created from GTFS files
    private IMap<String, TransportTrip> tripsMap;
    private IMap<String, TransportStop> stopsMap;
    private IMap<Integer, TransportShape> shapesMap;
    private IMap<String, TransportRoute> routesMap; 
    private IMap<Integer, Integer> shapeRouteTypeMap;
    
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
                        Map<String, Integer> headerMap = new HashMap<>(); // Map for headers
                        IList<String> fileContent = readCsvFile(file, headerMap);  // Reading the CSV file
                        gtfsData.put(file.getName(), fileContent);
                        IMap<String, Integer> headerIMap = GamaMapFactory.wrap(Types.STRING, Types.INT, headerMap);
                        headerMaps.put(file.getName(), headerIMap); // Store in headerMaps
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
   
    /**
     * Creates TransportRoute, TransportTrip, and TransportStop objects from GTFS files.
     */
    @SuppressWarnings("unchecked")
    private void createTransportObjects(IScope scope) {
        System.out.println("Starting transport object creation...");

        routesMap = GamaMapFactory.create(Types.STRING, Types.get(TransportRoute.class)); 
        stopsMap = GamaMapFactory.create(Types.STRING, Types.get(TransportStop.class));   
        tripsMap = GamaMapFactory.create(Types.STRING, Types.get(TransportTrip.class));     
        shapesMap = GamaMapFactory.create(Types.INT, Types.get(TransportShape.class));	
        shapeRouteTypeMap = GamaMapFactory.create();

        // ** Création d'une table associant shapeId à routeId **
        IMap<Integer, String> shapeRouteMap = GamaMapFactory.create(Types.INT, Types.STRING); 

        // ** Récupération des types de lignes via routes.txt **
        IMap<String, Integer> routeTypeMap = GamaMapFactory.create(Types.STRING, Types.INT);
        IList<String> routesData = gtfsData.get("routes.txt");
        IMap<String, Integer> routesHeader = headerMaps.get("routes.txt");

        if (routesData != null && routesHeader != null) {
            int routeIdIndex = routesHeader.get("route_id");
            int routeTypeIndex = routesHeader.get("route_type");

            for (String line : routesData) {
                String[] fields = line.split(",");
                try {
                    String routeId = fields[routeIdIndex];
                    int routeType = Integer.parseInt(fields[routeTypeIndex]);
                    routeTypeMap.put(routeId, routeType);
                } catch (Exception e) {
                    System.err.println("[ERROR] Invalid routeType in routes.txt: " + line + " -> " + e.getMessage());
                }
            }
        }

        // ** Création des arrêts de transport à partir de stops.txt **
        IList<String> stopsData = gtfsData.get("stops.txt");
        IMap<String, Integer> headerIMap = headerMaps.get("stops.txt"); 

        if (stopsData != null && headerIMap != null) {
            int stopIdIndex = headerIMap.get("stop_id");
            int stopNameIndex = headerIMap.get("stop_name");
            int stopLatIndex = headerIMap.get("stop_lat");
            int stopLonIndex = headerIMap.get("stop_lon");

            for (String line : stopsData) {
                String[] fields = line.split(",");
                try {
                    String stopId = fields[stopIdIndex];
                    String stopName = fields[stopNameIndex];
                    double stopLat = Double.parseDouble(fields[stopLatIndex]);
                    double stopLon = Double.parseDouble(fields[stopLonIndex]);

                    if (stopId.startsWith("stop_point")) {
                        TransportStop stop = new TransportStop(stopId, stopName, stopLat, stopLon, scope);
                        stopsMap.put(stopId, stop);
                    }
                } catch (Exception e) {
                    System.err.println("[ERROR] Processing stop line: " + line + " -> " + e.getMessage());
                }
            }
        }

        System.out.println("Finished creating TransportStop objects.");

        // ** Création des TransportShape à partir de shapes.txt **
        IList<String> shapesData = gtfsData.get("shapes.txt");
        IMap<String, Integer> headerMap = headerMaps.get("shapes.txt");

        if (shapesData != null && headerMap != null) {
            int shapeIdIndex = headerMap.get("shape_id");
            int latIndex = headerMap.get("shape_pt_lat");
            int lonIndex = headerMap.get("shape_pt_lon");

            for (String line : shapesData) {
                String[] fields = line.split(",");
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
                    System.err.println("[ERROR] Processing shape line: " + line + " -> " + e.getMessage());
                }
            }
        }

        System.out.println("Finished collecting points for TransportShape objects.");

        // ** Création des TransportTrip et remplissage de shapeRouteMap **
        System.out.println("[INFO] Creating TransportTrip objects and populating shapeRouteMap...");

        IList<String> tripsData = gtfsData.get("trips.txt");
        IMap<String, Integer> tripsHeaderMap = headerMaps.get("trips.txt");

        if (tripsData != null && tripsHeaderMap != null) {
            int routeIdIndex = tripsHeaderMap.get("route_id");
            int tripIdIndex = tripsHeaderMap.get("trip_id");
            int shapeIdIndex = tripsHeaderMap.get("shape_id");

            for (String line : tripsData) {
                String[] fields = line.split(",");
                try {
                    String routeId = fields[routeIdIndex];
                    int tripId = Integer.parseInt(fields[tripIdIndex]);
                    int shapeId = Integer.parseInt(fields[shapeIdIndex]);

                    TransportTrip trip = tripsMap.get(tripId);
                    if (trip == null) {
                        trip = new TransportTrip(routeId, "", tripId, 0, shapeId);
                        tripsMap.put(String.valueOf(tripId), trip);
                    }

                    if (routeTypeMap.containsKey(routeId)) {
                        int routeType = routeTypeMap.get(routeId);
                        shapeRouteTypeMap.put(shapeId, routeType);
                    }

                    shapeRouteMap.put(shapeId, routeId);
                    
                 // Ajouter tripId à TransportShape correspondant
                    if (shapesMap.containsKey(shapeId)) {
                        TransportShape shape = shapesMap.get(shapeId);
                        shape.setTripId(tripId);
                        System.out.println("[DEBUG] Assigned tripId=" + tripId + " to shapeId=" + shapeId);
                    } else {
                        System.err.println("[ERROR] No shape found for shapeId=" + shapeId);
                    }
                    System.out.println("[DEBUG] Stored in shapeRouteMap: ShapeId=" + shapeId + " -> RouteId=" + routeId);
                } catch (Exception e) {
                    System.err.println("[ERROR] Invalid trip line in trips.txt: " + line + " -> " + e.getMessage());
                }
            }
        }

        // ** Vérification du contenu de shapeRouteMap avant l’assignation **
        System.out.println("[DEBUG] Final content of shapeRouteMap:");
        for (Map.Entry<Integer, String> entry : shapeRouteMap.entrySet()) {
            System.out.println("ShapeId=" + entry.getKey() + " -> RouteId=" + entry.getValue());
        }

        // ** Assignation des routeId aux TransportShape **
        System.out.println("[INFO] Assigning routeId to TransportShapes...");
        for (TransportShape shape : shapesMap.values()) {
            int shapeId = shape.getShapeId();
            if (shapeRouteMap.containsKey(shapeId)) {
                String routeId = shapeRouteMap.get(shapeId);
                shape.setRouteId(routeId);
                System.out.println("[DEBUG] Assigned routeId=" + routeId + " to shapeId=" + shapeId);
            } else {
                System.err.println("[ERROR] No routeId found for shapeId=" + shapeId);
            }
        }

        // ** Assignation des routeType aux TransportShape et TransportTrip **
        for (TransportShape shape : shapesMap.values()) {
            int shapeId = shape.getShapeId();
            if (shapeRouteTypeMap.containsKey(shapeId)) {
                shape.setRouteType(shapeRouteTypeMap.get(shapeId));
                System.out.println("[INFO] Shape ID " + shapeId + " assigned routeType " + shape.getRouteType());
            } else {
                System.err.println("[ERROR] No routeType found for Shape ID " + shapeId);
            }
        }

        for (TransportTrip trip : tripsMap.values()) {
            int shapeId = trip.getShapeId();
            if (shapeRouteTypeMap.containsKey(shapeId)) {
                trip.setRouteType(shapeRouteTypeMap.get(shapeId));
                System.out.println("[INFO] Trip ID " + trip.getTripId() + " assigned routeType " + trip.getRouteType());
            }
        }

        System.out.println("[INFO] Finished assigning routeType to TransportShape and TransportTrip.");
        System.out.println("[INFO] Calling computeDepartureInfo...");
        computeDepartureInfo(scope);
        System.out.println("[INFO] computeDepartureInfo completed.");
    }


    /**
     * Reads a CSV file and returns its content as an IList.
     */
    private IList<String> readCsvFile(File file, Map<String, Integer> headerMap) throws IOException {
        IList<String> content = GamaListFactory.create();
        if (!file.isFile()) {
            throw new IOException(file.getAbsolutePath() + " is not a valid file.");
        }
        try (BufferedReader br = new BufferedReader(new FileReader(file))) {
            String line;
            // Read the header line
            String headerLine = br.readLine();
            if (headerLine != null) {
                String[] headers = headerLine.split(",");
                for (int i = 0; i < headers.length; i++) {
                    headerMap.put(headers[i].trim(), i);
                }
            }

            // Read the rest of the file
            while ((line = br.readLine()) != null) {
                content.add(line);
            }
        }
        return content;
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
    
    public void computeDepartureInfo(IScope scope) {
        System.out.println("Starting computeDepartureInfo...");

        IList<String> stopTimesData = gtfsData.get("stop_times.txt");
        IMap<String, Integer> stopTimesHeader = headerMaps.get("stop_times.txt");

        if (stopTimesData == null || stopTimesHeader == null) {
            System.err.println("[ERROR] stop_times.txt data or headers are missing.");
            return;
        }

        int tripIdIndex = stopTimesHeader.get("trip_id");
        int stopIdIndex = stopTimesHeader.get("stop_id");
        int departureTimeIndex = stopTimesHeader.get("departure_time");

        // 📌 Stocker les routeTypes associés aux arrêts
        @SuppressWarnings("unchecked")
		IMap<String, IList<Integer>> stopRouteTypes = GamaMapFactory.create(Types.STRING, Types.LIST);

        // 🔹 Étape 1 : Associer les trips aux arrêts et horaires
        for (String line : stopTimesData) {
            String[] fields = line.split(",");
            try {
                String tripId = fields[tripIdIndex]; // ✅ tripId en String
                String stopId = fields[stopIdIndex];
                String departureTime = fields[departureTimeIndex];

                TransportTrip trip = tripsMap.get(tripId);
                if (trip == null) continue;
                trip.addStop(stopId);
                trip.addStopDetail(stopId, departureTime);

                trip.addStop(stopId);
                trip.addStopDetail(stopId, departureTime);

                TransportStop stop = stopsMap.get(stopId);
                if (stop != null) {
                    int tripRouteType = trip.getRouteType();
                    if (tripRouteType != -1 && stop.getRouteType() == -1) {
                        stop.setRouteType(tripRouteType);
                    }
                    // ✅ Add tripId -> shapeId in the stop
                    stop.addTripShapePair(tripId, trip.getShapeId());
                }

            } catch (Exception e) {
                System.err.println("[ERROR] Error processing stop_times line: " + line + " -> " + e.getMessage());
            }
        }

        // 🔹 Étape 2 : Trier les trips selon l'heure du premier stop
        @SuppressWarnings("unchecked")
		IMap<String, IList<GamaPair<String, String>>> departureTripsInfo = GamaMapFactory.create(Types.STRING, Types.LIST);
        @SuppressWarnings("unchecked")
		IMap<String, String> tripDepartureTimes = GamaMapFactory.create(Types.STRING, Types.STRING);

        for (TransportTrip trip : tripsMap.values()) {
            IList<String> stopsInOrder = trip.getStopsInOrder();
            IList<IMap<String, Object>> stopDetails = trip.getStopDetails();
            IList<GamaPair<String, String>> stopPairs = GamaListFactory.create(Types.PAIR);

            if (stopsInOrder.isEmpty()) {
                System.err.println("[ERROR] Trip " + trip.getTripId() + " has no stops.");
                continue;
            }
            if (stopDetails.size() != stopsInOrder.size()) {
                System.err.println("[ERROR] Mismatch between stops and stop details for Trip ID " + trip.getTripId());
                continue;
            }

            // ✅ Récupérer l'heure de départ du premier stop
            String firstDepartureTime = stopDetails.get(0).get("departureTime").toString();
            if (firstDepartureTime == null || firstDepartureTime.isEmpty()) {
                System.err.println("[ERROR] No departure time found for Trip ID " + trip.getTripId());
                continue;
            }

            // 🔹 Associer `tripId` à `firstDepartureTime`
            tripDepartureTimes.put(String.valueOf(trip.getTripId()), firstDepartureTime);

            // 🔹 Ajouter les stops et horaires au trip
            for (int i = 0; i < stopsInOrder.size(); i++) {
                String stopId = stopsInOrder.get(i);
                String departureTime = stopDetails.get(i).get("departureTime").toString();
                stopPairs.add(new GamaPair<>(stopId, departureTime, Types.STRING, Types.STRING));
            }

            departureTripsInfo.put(String.valueOf(trip.getTripId()), stopPairs);
        }

        // 🔹 Étape 3 : Trier les trips par ordre croissant d'heure de départ
        System.out.println("[DEBUG] Sorting trips by departure time...");
        IList<String> sortedTripIds = GamaListFactory.create();

        tripDepartureTimes.entrySet().stream()
            .sorted(Map.Entry.comparingByValue()) // Trie les trips selon l'heure de départ
            .forEachOrdered(entry -> sortedTripIds.add(entry.getKey()));

        // 🔹 Étape 4 : Affecter les trips triés aux arrêts de départ
        for (String tripId : sortedTripIds) {
            IList<GamaPair<String, String>> stopPairs = departureTripsInfo.get(tripId);

            if (stopPairs == null || stopPairs.isEmpty()) {
                System.err.println("[ERROR] No stopPairs found for tripId=" + tripId);
                continue;
            }

            // ✅ Récupérer le premier arrêt du trip
            String firstStopId = stopPairs.get(0).key;
            TransportStop firstStop = stopsMap.get(firstStopId);

            if (firstStop != null) {
                firstStop.ensureDepartureTripsInfo();
                firstStop.addStopPairs(tripId, stopPairs);
                System.out.println("[DEBUG] Stored tripId " + tripId + " in stop " + firstStopId);
            } else {
                System.err.println("[ERROR] First stop not found for sorted tripId=" + tripId);
            }
        }

        // 📌 Étape 5 : Affecter le routeType dominant à chaque arrêt
        for (TransportStop stop : stopsMap.values()) {
            if (stopRouteTypes.containsKey(stop.getStopId())) {
                IList<Integer> routeTypes = stopRouteTypes.get(stop.getStopId());
                int mostCommonRouteType = routeTypes.get(0); // On prend le premier (par défaut)

                // 🎯 Choisir le `routeType` le plus fréquent
                Map<Integer, Integer> frequencyMap = new HashMap<>();
                for (int type : routeTypes) {
                    frequencyMap.put(type, frequencyMap.getOrDefault(type, 0) + 1);
                }
                mostCommonRouteType = frequencyMap.entrySet().stream()
                        .max(Map.Entry.comparingByValue()) // Choisir le type le plus fréquent
                        .get().getKey();

                //  On ne remplace pas un routeType déjà existant
                if (stop.getRouteType() == -1) {
                    stop.setRouteType(mostCommonRouteType);
                    System.out.println("[INFO] Assigned most common routeType=" + mostCommonRouteType + " to stopId=" + stop.getStopId());
                } else {
                    System.out.println("[INFO] StopId " + stop.getStopId() + " already has a routeType=" + stop.getRouteType());
                }
            } else {
                System.err.println("[WARNING] Stop ID " + stop.getStopId() + " has no associated trips, keeping routeType=-1.");
            }
        }

        System.out.println("computeDepartureInfo completed successfully.");
    }


}