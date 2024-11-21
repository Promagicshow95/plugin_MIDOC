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

import org.apache.commons.io.FileUtils;

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
    private IMap<String, IMap<String, Integer>> headerMaps = GamaMapFactory.create(Types.STRING, Types.get(IMap.class));

    // Collections for objects created from GTFS files
//    private IMap<String, TransportRoute> routesMap;
    private IMap<Integer, TransportTrip> tripsMap;
    private IMap<String, TransportStop> stopsMap;

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
        
        // Check the validity of the directory
//        System.out.println("Checking the validity of the GTFS directory...");
//        checkValidity(scope);  
//        System.out.println("Directory validation completed.");

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
     * Method to retrieve the list of trips (TransportTrip) from tripsMap.
     * @return List of transport stops
     */
    
    public List<TransportTrip> getTrips() {
    	List<TransportTrip> tripList = new ArrayList<>(tripsMap.values());
    	System.out.println("Number of created trip : " + tripList.size());
        return tripList;
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
//        routesMap = GamaMapFactory.create(Types.STRING, Types.get(TransportRoute.class)); // Using GamaMap for routesMap
        stopsMap = GamaMapFactory.create(Types.STRING, Types.get(TransportStop.class));   // Using GamaMap for stopMap
        tripsMap = GamaMapFactory.create(Types.INT, Types.get(TransportTrip.class));      // Using GamaMap for tripMap

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
                    
                 // Pass the scope to the TransportStop constructor for CRS transformation
                    TransportStop stop = new TransportStop(stopId, stopName, stopLat, stopLon, scope);
                    stopsMap.put(stopId, stop);
                    System.out.println("Created TransportStop: " + stopId);
                } catch (Exception e) {
                    System.err.println("Error processing line: " + line + " -> " + e.getMessage());
                }
            }
        } else {
            System.err.println("stops.txt data or headers are missing.");
        }

        System.out.println("Finished creating TransportStop objects.");
        

//        // Create TransportRoute objects from routes.txt
//        IList<String> routesData = gtfsData.get("routes.txt");
//        if (routesData != null) {
//            for (String line : routesData) {
//                String[] fields = line.split(",");
//                String routeId = fields[0];
//                String shortName = fields[1];
//                String longName = fields[2];
//                int type = Integer.parseInt(fields[3]);
//                String color = fields[4];
//                TransportRoute route = new TransportRoute(routeId, shortName, longName, type, color);
//                routesMap.put(routeId, route); // Storage in routesMap
//                System.out.println("Created TransportRoute object: " + routeId);
//            }
//        }

//        // Create TransportTrip objects from trips.txt
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
    	System.out.println("Computing envelope - returning null.");
        return null;
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