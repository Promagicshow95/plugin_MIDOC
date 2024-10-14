package gama.extension.GTFS;

import gama.core.common.geometry.Envelope3D;
import gama.core.runtime.IScope;
import gama.core.runtime.exceptions.GamaRuntimeException;
import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.IList;
import gama.core.util.file.GamaFile;
import gama.gaml.types.IType;
import gama.gaml.types.Types;
import gama.gaml.types.IContainerType;
import gama.annotations.precompiler.IConcept;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.annotations.precompiler.GamlAnnotations.example;
import gama.annotations.precompiler.GamlAnnotations.file;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/**
 * Lecture et traitement des fichiers GTFS dans GAMA. Cette classe lit plusieurs fichiers GTFS
 * et crée des objets TransportRoute, TransportTrip, et TransportStop.
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
    
    // Fichiers obligatoires pour les données GTFS
    private static final String[] REQUIRED_FILES = {
        "agency.txt", "routes.txt", "trips.txt", "calendar.txt", "stop_times.txt", "stops.txt"
    };

    // Structure de données pour stocker les fichiers GTFS
    private Map<String, IList<String>> gtfsData;

    // Collections pour les objets créés à partir des fichiers GTFS
    private Map<String, TransportRoute> routesMap;
    private Map<String, TransportStop> stopsMap;
    private Map<Integer, TransportTrip> tripsMap;

    /**
     * Constructeur pour la lecture des fichiers GTFS.
     *
     * @param scope    Le contexte de simulation dans GAMA.
     * @param pathName Le chemin du répertoire contenant les fichiers GTFS.
     * @throws GamaRuntimeException Si un problème survient lors du chargement des fichiers.
     */
    @doc (
            value = "Ce constructeur permet de charger les fichiers GTFS à partir d'un répertoire spécifié.",
            examples = { @example (value = "GTFS_reader gtfs <- GTFS_reader(scope, \"path_to_gtfs_directory\");")})
    public GTFS_reader(final IScope scope, final String pathName) throws GamaRuntimeException {
        super(scope, pathName);
<<<<<<< HEAD
        checkValidity(scope, pathName);  // Vérifier si le dossier est valide
=======
        checkValidity(scope);
>>>>>>> c69b188460e52a813901251fab6e808072ec85f6
        loadGtfsFiles(scope, pathName);
        createTransportObjects(scope);
    }

    /**
     * Méthode pour vérifier la validité du dossier
     *
     * @param scope    Le contexte de simulation dans GAMA.
     * @param pathName Le chemin du répertoire contenant les fichiers GTFS.
     * @throws GamaRuntimeException Si le dossier n'est pas valide ou ne contient pas les fichiers nécessaires.
     */
    private void checkValidity(final IScope scope, final String pathName) throws GamaRuntimeException {
        File folder = new File(pathName);

        // Vérifier si le chemin est valide
        if (!folder.exists() || !folder.isDirectory()) {
            throw GamaRuntimeException.error("Le chemin fourni pour les fichiers GTFS est invalide.", scope);
        }

        // Vérifier si les fichiers requis sont présents
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

        // Si des fichiers requis manquent, déclencher une exception
        if (!requiredFilesSet.isEmpty()) {
            throw GamaRuntimeException.error("Fichiers GTFS manquants : " + requiredFilesSet, scope);
        }
    }

    /**
     * Charge les fichiers GTFS et vérifie si tous les fichiers requis sont présents.
     */
    private void loadGtfsFiles(final IScope scope, final String pathName) throws GamaRuntimeException {
        gtfsData = new HashMap<>();

        try {
            File folder = new File(pathName);
            File[] files = folder.listFiles();
            if (files != null) {
                for (File file : files) {
                    String fileName = file.getName();
                    if (fileName.endsWith(".txt")) {
                        IList<String> fileContent = readCsvFile(file);
                        gtfsData.put(fileName, fileContent);
                    }
                }
            }
        } catch (Exception e) {
            throw GamaRuntimeException.create(e, scope);
        }
    }

    /**
     * Crée des objets TransportRoute, TransportTrip, et TransportStop à partir des fichiers GTFS.
     */
    private void createTransportObjects(IScope scope) {
    	routesMap = GamaMapFactory.create(Types.STRING, Types.get(TransportRoute.class));
    	stopsMap = GamaMapFactory.create(Types.STRING, Types.get(TransportStop.class));
    	tripsMap = GamaMapFactory.create(Types.INT, Types.get(TransportTrip.class));


        // Créer des objets TransportStop à partir de stops.txt
        IList<String> stopsData = gtfsData.get("stops.txt");
        if (stopsData != null) {
            for (String line : stopsData) {
                String[] fields = line.split(",");
                String stopId = fields[0];
                String stopName = fields[1];
                double stopLat = Double.parseDouble(fields[2]);
                double stopLon = Double.parseDouble(fields[3]);
                TransportStop stop = new TransportStop(stopId, stopName, stopLat, stopLon);
                stopsMap.put(stopId, stop);
            }
        }

        // Créer des objets TransportRoute à partir de routes.txt
        IList<String> routesData = gtfsData.get("routes.txt");
        if (routesData != null) {
            for (String line : routesData) {
                String[] fields = line.split(",");
                String routeId = fields[0];
                String shortName = fields[1];
                String longName = fields[2];
                int type = Integer.parseInt(fields[3]);
                String color = fields[4];
                TransportRoute route = new TransportRoute(routeId, shortName, longName, type, color);
                routesMap.put(routeId, route);
            }
        }

        // Créer des objets TransportTrip à partir de trips.txt
        IList<String> tripsData = gtfsData.get("trips.txt");
        if (tripsData != null) {
            for (String line : tripsData) {
                String[] fields = line.split(",");
                String routeId = fields[0];
                String serviceId = fields[1];
                int tripId = Integer.parseInt(fields[2]);
                int directionId = Integer.parseInt(fields[3]);
                int shapeId = Integer.parseInt(fields[4]);
                TransportRoute route = routesMap.get(routeId);
                TransportTrip trip = new TransportTrip(routeId, serviceId, tripId, directionId, shapeId, route);
                tripsMap.put(tripId, trip);
            }
        }
    }

    /**
     * Lit un fichier CSV et renvoie son contenu sous forme de IList.
     */
    private IList<String> readCsvFile(File file) throws IOException {
        IList<String> content = GamaListFactory.create();
        try (BufferedReader br = new BufferedReader(new FileReader(file))) {
            String line;
            while ((line = br.readLine()) != null) {
                content.add(line);
            }
        }
        return content;
    }

    @Override
    protected void fillBuffer(final IScope scope) throws GamaRuntimeException {
        if (gtfsData == null) {
            loadGtfsFiles(scope, getPath(scope));
        }
    }

    @Override
    public IList<String> getAttributes(final IScope scope) {
        Set<String> keySet = gtfsData.keySet();
        return GamaListFactory.createWithoutCasting(Types.STRING, keySet.toArray(new String[0]));
    }

    @Override
    public IContainerType<IList<String>> getGamlType() {
        return Types.FILE.of(Types.STRING, Types.STRING);
    }

    @Override
    public Envelope3D computeEnvelope(final IScope scope) {
        return null;
    }

	@Override
	protected void checkValidity(final IScope scope) throws GamaRuntimeException {
		final File file = getFile(scope);
		if (file == null || !file.exists()) throw GamaRuntimeException.error(
				"The folder " + getFile(scope).getAbsolutePath() + " does not exist. Please use 'new_folder' instead",
				scope);
		if (!getFile(scope).isDirectory())
			throw GamaRuntimeException.error(getFile(scope).getAbsolutePath() + "is not a folder", scope);
	}
    
    
    // Ajout d'une méthode pour accéder à une route spécifique
    public TransportRoute getRoute(String routeId) {
        return routesMap.get(routeId);
    }

    // Ajout d'une méthode pour accéder à un trajet spécifique
    public TransportTrip getTrip(int tripId) {
        return tripsMap.get(tripId);
    }

    // Ajout d'une méthode pour accéder à un arrêt spécifique
    public TransportStop getStop(String stopId) {
        return stopsMap.get(stopId);
    }
}
