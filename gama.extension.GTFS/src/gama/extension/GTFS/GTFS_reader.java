package gama.extension.GTFS;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.locationtech.jts.geom.Polygon;

import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.annotations.precompiler.GamlAnnotations.example;
import gama.annotations.precompiler.GamlAnnotations.file;
import gama.annotations.precompiler.IConcept;
import gama.core.common.geometry.Envelope3D;
import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.GamaShape;
import gama.core.metamodel.shape.GamaShapeFactory;
import gama.core.metamodel.shape.IShape;
import gama.core.runtime.IScope;
import gama.core.runtime.exceptions.GamaRuntimeException;
import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.IList;
import gama.core.util.IMap;
import gama.core.util.file.GamaFile;
import gama.core.util.file.GamaGisFile;
import gama.gaml.operators.spatial.SpatialProjections;
import gama.gaml.types.IContainerType;
import gama.gaml.types.IType;
import gama.gaml.types.Types;

import org.geotools.data.DataUtilities;
import org.geotools.data.FileDataStore;
import org.geotools.data.FileDataStoreFinder;
import org.geotools.data.simple.SimpleFeatureStore;
import org.geotools.data.simple.SimpleFeatureCollection;
import org.geotools.feature.simple.SimpleFeatureBuilder;
import org.geotools.feature.simple.SimpleFeatureTypeBuilder;
import org.locationtech.jts.geom.Polygon;
import org.opengis.feature.simple.SimpleFeature;

import java.io.File;

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
    private IMap<String, IMap<String, Integer>> headerMaps = GamaMapFactory.create(Types.STRING, Types.get(IMap.class));

    // Collections for objects created from GTFS files
//    private IMap<String, TransportRoute> routesMap;
    private IMap<Integer, TransportTrip> tripsMap;
    private IMap<String, TransportStop> stopsMap;
    private IMap<Integer, TransportShape> shapesMap;
    private IMap<String, TransportRoute> routesMap; 
    

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
            System.out.println("GTFS path used: " + pathName);  // For testing outside of GAMA
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
        System.out.println("Number of created stop : " + stopList.size());
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
     * @return List of transport stops
     */
    
    public List<TransportTrip> getTrips() {
    	List<TransportTrip> tripList = new ArrayList<>(tripsMap.values());
    	System.out.println("Number of created trip : " + tripList.size());
        return tripList;
    }
    
    /**
     * Method to retrieve the list of routes (TransportRoute) from routesMap.
     * @return List of transport route
     */
    public List<TransportRoute> getRoutes() {
        return new ArrayList<>(routesMap.values());
    }


    /**
     * Method to verify the directory's validity.
     *
     * @param scope    The simulation context in GAMA.
     * @param pathName The directory path containing GTFS files.
     * @throws GamaRuntimeException If the directory is invalid or does not contain required files.
     */
    @Override
    protected void checkValidity(final IScope scope) throws GamaRuntimeException {
    	
    	 System.out.println("Starting directory validity check...");

    	File folder = getFile(scope);
        // Check if the path is valid and is a directory
        if (!folder.exists() || !folder.isDirectory()) {
            throw GamaRuntimeException.error("The provided path for GTFS files is invalid. Ensure it is a directory containing .txt files.", scope);
        }

        // Check if the required files (e.g., stops.txt, routes.txt) are present in the folder
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

        // If required files are missing, throw an exception
        if (!requiredFilesSet.isEmpty()) {
            throw GamaRuntimeException.error("Missing GTFS files: " + requiredFilesSet, scope);
        }
        System.out.println("Directory validity check completed.");
    }


    /**
     * Loads GTFS files and verifies if all required files are present.
     */
    private void loadGtfsFiles(final IScope scope) throws GamaRuntimeException {
        gtfsData = GamaMapFactory.create(Types.STRING, Types.LIST); // Use GamaMap for storing GTFS files
        headerMaps = GamaMapFactory.create(Types.STRING, Types.get(IMap.class));
        try {
            File folder = this.getFile(scope);
            File[] files = folder.listFiles();  // List of files in the folder
            if (files != null) {
                for (File file : files) {
                    if (file.isFile() && file.getName().endsWith(".txt")) {
                        System.out.println("Reading file: " + file.getName());
                        Map<String, Integer> headerMap = new HashMap<>(); // Map for headers
                        IList<String> fileContent = readCsvFile(file, headerMap);  // Reading the CSV file
                        gtfsData.put(file.getName(), fileContent);
                        IMap<String, Integer> headerIMap = GamaMapFactory.wrap(Types.STRING, Types.INT, headerMap);
                        headerMaps.put(file.getName(), headerIMap); // Stocker dans headerMaps
                        System.out.println("Headers loaded for file: " + file.getName() + " -> " + headerIMap);
                        System.out.println("Finished reading file: " + file.getName());
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
    private Map<String, Integer> getHeaderMap(String fileName) {
        IList<String> headers = gtfsData.get(fileName + "_headers");
        if (headers == null) return null;
        Map<String, Integer> headerMap = new HashMap<>();
        for (int i = 0; i < headers.size(); i++) {
            headerMap.put(headers.get(i), i);
        }
        return headerMap;
    }

    /**
     * Creates TransportRoute, TransportTrip, and TransportStop objects from GTFS files.
     */
    private void createTransportObjects(IScope scope) {
    	System.out.println("Starting transport object creation...");
        routesMap = GamaMapFactory.create(Types.STRING, Types.get(TransportRoute.class)); // Using GamaMap for routesMap
        stopsMap = GamaMapFactory.create(Types.STRING, Types.get(TransportStop.class));   // Using GamaMap for stopMap
        tripsMap = GamaMapFactory.create(Types.INT, Types.get(TransportTrip.class));      // Using GamaMap for tripMap
        shapesMap = GamaMapFactory.create(Types.INT, Types.get(TransportShape.class));
        
        
     // Create TransportStop objects from stops.txt
        IList<String> stopsData = gtfsData.get("stops.txt");
        // Use header map stored in gtfsData
        IMap<String, Integer> headerIMap = headerMaps.get("stops.txt"); // Retrieve headers from headerMaps

        if (stopsData == null || stopsData.isEmpty()) {
            System.err.println("stopsData is null or empty.");
        } else {
            System.out.println("stopsData size: " + stopsData.size());
        }

        if (headerIMap == null) {
            System.err.println("headerIMap for stops.txt is null.");
        } else {
            System.out.println("Headers for stops.txt: " + headerIMap);
        }

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

                    // Filter only stop_point stop_ids
                    if (stopId.startsWith("stop_point")) {
                        TransportStop stop = new TransportStop(stopId, stopName, stopLat, stopLon, scope);
                        stopsMap.put(stopId, stop);
                        System.out.println("Created TransportStop: " + stopId);
                    } else {
                        System.out.println("Skipped non stop_point: " + stopId);
                    }
                } catch (Exception e) {
                    System.err.println("Error processing line: " + line + " -> " + e.getMessage());
                }
            }
        } else {
            System.err.println("stops.txt data or headers are missing.");
        }
        
     // Add this at the end of createTransportObjects(IScope scope)
        System.out.println("Calling computeStopTripAssociations...");
        computeStopTripAssociations(scope);
        System.out.println("computeStopTripAssociations completed.");


        System.out.println("Finished creating TransportStop objects.");
        
     // Create TransporShape objects from shapes.txt
        IList<String> shapesData = gtfsData.get("shapes.txt");
        IMap<String, Integer> headerMap = headerMaps.get("shapes.txt");
        if (shapesData != null && headerMap != null) {
            System.out.println("Processing shapes.txt...");
            int shapeIdIndex = headerMap.get("shape_id");
            int latIndex = headerMap.get("shape_pt_lat");
            int lonIndex = headerMap.get("shape_pt_lon");

            for (String line : shapesData) {
                String[] fields = line.split(",");
                try {
                    int shapeId = Integer.parseInt(fields[shapeIdIndex]);
                    double lat = Double.parseDouble(fields[latIndex]);
                    double lon = Double.parseDouble(fields[lonIndex]);

                    // Crée ou récupère un objet TransportShape
                    TransportShape shape = shapesMap.get(shapeId);
                    if (shape == null) {
                        shape = new TransportShape(shapeId);
                        shapesMap.put(shapeId, shape);
                    }

                    // Add the point to shape
                    shape.addPoint(lat, lon, scope);
                } catch (Exception e) {
                    System.err.println("Error processing shape line: " + line + " -> " + e.getMessage());
                }
            }
            System.out.println("Finished creating TransportShape objects.");
        } else {
            System.err.println("shapes.txt data or headers are missing.");
        }
        
     // Convert each TransportShape into a polyline
        for (TransportShape shape : shapesMap.values()) {
            try {
                IShape polyline = shape.toPolyline(scope);
                System.out.println("Polyline created for Shape ID " + shape.getShapeId() + ": " + polyline);
            } catch (Exception e) {
                System.err.println("Error converting Shape ID " + shape.getShapeId() + " to polyline: " + e.getMessage());
            }
        }
        
        
        // Create TransportRoute objects from routes.txt
        IList<String> routesData = gtfsData.get("routes.txt");
        IMap<String, Integer> routesheaderMap = headerMaps.get("routes.txt");

        if (routesData != null && routesheaderMap != null) {
            System.out.println("Processing routes.txt...");

            int routeIdIndex = routesheaderMap.get("route_id");
            int shortNameIndex = routesheaderMap.get("route_short_name");
            int longNameIndex = routesheaderMap.get("route_long_name");
            int typeIndex = routesheaderMap.get("route_type");

            routesMap = GamaMapFactory.create(Types.STRING, Types.get(TransportRoute.class));

            for (String line : routesData) {
                try {
                    String[] fields = line.split(",");
                    String routeId = fields[routeIdIndex];
                    String shortName = fields[shortNameIndex];
                    String longName = fields[longNameIndex];
                    int type = Integer.parseInt(fields[typeIndex]);

                    TransportRoute route = new TransportRoute(routeId, shortName, longName, type);
                    routesMap.put(routeId, route);
                    System.out.println("Created TransportRoute: " + route);
                } catch (Exception e) {
                    System.err.println("Error processing route line: " + line + " -> " + e.getMessage());
                }
            }
        } else {
            System.err.println("routes.txt data or headers are missing.");
        }

        // Create TransportTrip objects from trips.txt
        IList<String> tripsData = gtfsData.get("trips.txt");
        IMap<String, Integer> tripsHeaderMap = headerMaps.get("trips.txt");
        if (tripsData != null && tripsHeaderMap != null) {
            System.out.println("Processing trips.txt...");
            int routeIdIndex = tripsHeaderMap.get("route_id");
            int serviceIdIndex = tripsHeaderMap.get("service_id");
            int tripIdIndex = tripsHeaderMap.get("trip_id");
            int directionIdIndex = tripsHeaderMap.get("direction_id");
            int shapeIdIndex = tripsHeaderMap.get("shape_id");

            for (String line : tripsData) {
                String[] fields = line.split(",");
                try {
                    String routeId = fields[routeIdIndex];
                    String serviceId = fields[serviceIdIndex];
                    int tripId = Integer.parseInt(fields[tripIdIndex]);
                    int directionId = Integer.parseInt(fields[directionIdIndex]);
                    int shapeId = Integer.parseInt(fields[shapeIdIndex]);

                    // Create the TransportTrip object (ATTENTION,in this line null replace TransportRoute latter)
                    TransportTrip trip = new TransportTrip(routeId, serviceId, tripId, directionId, shapeId, null);
                    tripsMap.put(tripId, trip);
                    System.out.println("Created TransportTrip: " + tripId);
                } catch (Exception e) {
                    System.err.println("Error processing trip line: " + line + " -> " + e.getMessage());
                }
            }
            System.out.println("Finished creating TransportTrip objects.");
        } else {
            System.err.println("trips.txt data or headers are missing.");
        }
        
        System.out.println("Transport object creation completed.");
    }
    


    /**
     * Reads a CSV file and returns its content as an IList.
     */
    private IList<String> readCsvFile(File file, Map<String, Integer> headerMap) throws IOException {
        IList<String> content = GamaListFactory.create();
        if (!file.isFile()) {
            throw new IOException(file.getAbsolutePath() + " is not a valid file.");
        }
        System.out.println("Reading file: " + file.getAbsolutePath());
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
        System.out.println("Finished reading file: " + file.getAbsolutePath());
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
        System.out.println("Calculating envelope for GTFS stops...");

        if (stopsMap == null || stopsMap.isEmpty()) {
            System.err.println("No stops available to compute the envelope.");
            return Envelope3D.EMPTY;
        }

        // Ensure CRS consistency
        Envelope3D envelope = Envelope3D.create();
        for (TransportStop stop : stopsMap.values()) {
            try {
                GamaPoint location = stop.getLocation();
                if (location == null) {
                    System.err.println("Skipping stop with null location: " + stop.getStopId());
                    continue;
                }
                
                // Transform to match the CRS of the shapefile
                IShape transformedLocation = SpatialProjections.to_GAMA_CRS(scope, location, "EPSG:XXXX"); // Replace with shapefile CRS
                envelope.expandToInclude(transformedLocation.getLocation());
            } catch (Exception e) {
                System.err.println("Error adding stop to envelope: " + stop.getStopId() + " -> " + e.getMessage());
            }
        }

        System.out.println("Computed envelope: " + envelope);
        
        
        return envelope;
    }
    
    public GamaShape getEnvelopeAsShape(final IScope scope) {
        Envelope3D envelope = computeEnvelope(scope); // Calculer l'enveloppe

        if (envelope.isNull()) {
            System.err.println("Envelope is empty. Cannot create shape.");
            return null;
        }

        try {
            // Convertir l'enveloppe en un polygone
            Polygon polygon = envelope.toGeometry();
            // Retourner une forme GAMA (GamaShape) pour utilisation dans la simulation
            return GamaShapeFactory.createFrom(polygon);
        } catch (Exception e) {
            System.err.println("Error creating shape from envelope: " + e.getMessage());
            return null;
        }
    }
    
    /**
     * Compute trips and their predecessors for each stop.
     */
    public void computeStopTripAssociations(IScope scope) {
        IList<String> stopTimesData = gtfsData.get("stop_times.txt");
        IMap<String, Integer> stopTimesHeader = headerMaps.get("stop_times.txt");

        if (stopTimesData == null || stopTimesHeader == null) {
            System.err.println("Erreur : Les données ou en-têtes de stop_times.txt sont null.");
            return;
        }

        int tripIdIndex = stopTimesHeader.get("trip_id");
        int stopIdIndex = stopTimesHeader.get("stop_id");
        int stopSequenceIndex = stopTimesHeader.get("stop_sequence");

        System.out.println("Indices des colonnes : trip_id = " + tripIdIndex +
                ", stop_id = " + stopIdIndex +
                ", stop_sequence = " + stopSequenceIndex);

        Map<String, Integer> stopSequences = new HashMap<>();
        Map<Integer, List<TransportStop>> tripStopsMap = new HashMap<>();

        // Construire les séquences et organiser les arrêts
        for (String line : stopTimesData) {
            String[] fields = line.split(",");
            int tripId;
            String stopId;
            int sequence;

            try {
                tripId = Integer.parseInt(fields[tripIdIndex]);
                stopId = fields[stopIdIndex];
                sequence = Integer.parseInt(fields[stopSequenceIndex]);
            } catch (NumberFormatException | ArrayIndexOutOfBoundsException e) {
                System.err.println("Erreur lors du traitement de la ligne : " + line);
                continue;
            }

            System.out.println("Traitement : tripId = " + tripId + ", stopId = " + stopId + ", sequence = " + sequence);

            stopSequences.put(stopId, sequence);

            TransportStop stop = stopsMap.get(stopId);
            if (stop == null) {
                System.err.println("Erreur : Aucun arrêt trouvé pour stopId = " + stopId);
                continue;
            }

            tripStopsMap.computeIfAbsent(tripId, id -> new ArrayList<>()).add(stop);
        }

        // Trier et traiter les arrêts par trajet
        tripStopsMap.forEach((tripId, stops) -> {
            System.out.println("Traitement des arrêts pour tripId = " + tripId);

            // Tri des arrêts par séquence
            stops.sort((a, b) -> Integer.compare(
                stopSequences.get(a.getStopId()),
                stopSequences.get(b.getStopId())
            ));

            System.out.println("Arrêts triés pour tripId = " + tripId);

            for (int i = 0; i < stops.size(); i++) {
                TransportStop currentStop = stops.get(i);
                System.out.println("Arrêt actuel : " + currentStop.getStopId() + " (index = " + i + ")");

                // Récupérer les prédécesseurs
                List<TransportStop> predecessors = stops.subList(0, i);
                System.out.println("Prédécesseurs pour " + currentStop.getStopId() + ": " + predecessors);

                // Ajouter les prédécesseurs
                IList<TransportStop> gamaList = GamaListFactory.createWithoutCasting(
                    Types.get(TransportStop.class),
                    predecessors.toArray(new TransportStop[0])
                );

                currentStop.addTripWithPredecessors(tripId, gamaList);

                // Si c'est le dernier arrêt, définir comme destination
                if (i == stops.size() - 1) {
                	currentStop.addDestination(tripId, currentStop.getStopId());
                    System.out.println("Arrêt final pour tripId = " + tripId + ": " + currentStop.getStopId());
//                    currentStop.addDestination(tripId, currentStop.getStopId());
                }
            }
        });

        System.out.println("Traitement terminé.");
    }


    public TransportStop getStop(String stopId) {
        System.out.println("Getting stop with ID: " + stopId);
        TransportStop stop = stopsMap.get(stopId);
        if (stop != null) {
            System.out.println("Stop found: " + stopId);
        } else {
            System.out.println("Stop not found: " + stopId);
        }
        return stop;
    }
}