package gama.extension.GTFS;

import gama.core.common.geometry.Envelope3D;
import gama.core.runtime.IScope;
import gama.core.runtime.exceptions.GamaRuntimeException;
import gama.core.util.GamaListFactory;
import gama.core.util.IList;
import gama.core.util.GamaMapFactory;
import gama.core.util.IMap;
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
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
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
    private IMap<String, IList<String>> gtfsData;

    // Collections pour les objets créés à partir des fichiers GTFS
    private IMap<String, TransportRoute> routesMap;
    private IMap<String, TransportStop> stopsMap;
    private IMap<Integer, TransportTrip> tripsMap;

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
        
     // Débogage : Affichez le chemin du dossier GTFS dans la console GAMA
        if (scope != null && scope.getGui() != null) {
            scope.getGui().getConsole().informConsole("Chemin GTFS utilisé : " + pathName, scope.getSimulation());
        } else {
            System.out.println("Chemin GTFS utilisé : " + pathName);  // Pour les tests hors de GAMA
        }
        
//        checkValidity(scope, pathName);  // Vérifier si le dossier est valide
        loadGtfsFiles(scope, pathName);
        createTransportObjects(scope);
    }
    
    // Ajoutez ici un nouveau constructeur avec un seul paramètre String
    public GTFS_reader(final String pathName) throws GamaRuntimeException {
        super(null, pathName);  // Passez 'null' pour IScope car vous n'en avez pas besoin ici
 //       checkValidity(null, pathName);  // Vous pouvez passer 'null' si IScope n'est pas nécessaire pour cette vérification
        loadGtfsFiles(null, pathName);
        createTransportObjects(null);
    }
    
    /**
     * Méthode pour récupérer la liste des arrêts (TransportStop) à partir de stopsMap.
     * @return Liste des arrêts de transport
     */
    public List<TransportStop> getStops() {
        // Créer une liste Java à partir des valeurs dans stopsMap
        List<TransportStop> stopList = new ArrayList<>(stopsMap.values());
        return stopList;
    }

    /**
     * Méthode pour vérifier la validité du dossier
     *
     * @param scope    Le contexte de simulation dans GAMA.
     * @param pathName Le chemin du répertoire contenant les fichiers GTFS.
     * @throws GamaRuntimeException Si le dossier n'est pas valide ou ne contient pas les fichiers nécessaires.
     */
    @Override
	protected void checkValidity(final IScope scope) throws GamaRuntimeException { 
 //   private void checkValidity(final IScope scope, final String pathName) throws GamaRuntimeException {
   //     File folder = new File(pathName);
        File folder = getFile(scope);
        // Vérifier si le chemin est valide et est un répertoire
        if (!folder.exists() || !folder.isDirectory()) {
            throw GamaRuntimeException.error("Le chemin fourni pour les fichiers GTFS est invalide. Assurez-vous que c'est un dossier contenant des fichiers .txt", scope);
        }

        // Vérifier si les fichiers requis (comme stops.txt, routes.txt) sont présents dans le dossier
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
        gtfsData = GamaMapFactory.create(Types.STRING, Types.LIST); // Utilisation de GamaMap pour stocker les données GTFS

        try {
            File folder = new File(pathName);
            File[] files = folder.listFiles();  // Liste tous les fichiers dans le dossier
            if (files != null) {
                for (File file : files) {
                    // Vérifie si le fichier est un fichier et a l'extension .txt
                    if (file.isFile() && file.getName().endsWith(".txt")) {
                        IList<String> fileContent = readCsvFile(file);  // Lecture du fichier CSV
                        gtfsData.put(file.getName(), fileContent); // Stocker le contenu du fichier
                    }
                }
            }
        } catch (Exception e) {
            throw GamaRuntimeException.create(e, scope);  // Gestion des exceptions
        }
    }

    /**
     * Crée des objets TransportRoute, TransportTrip, et TransportStop à partir des fichiers GTFS.
     */
    private void createTransportObjects(IScope scope) {
        routesMap = GamaMapFactory.create(Types.STRING, Types.get(TransportRoute.class)); // Utilisation de GamaMap pour routesMap
        stopsMap = GamaMapFactory.create(Types.STRING, Types.get(TransportStop.class));   // Utilisation de GamaMap pour stopsMap
        tripsMap = GamaMapFactory.create(Types.INT, Types.get(TransportTrip.class));      // Utilisation de GamaMap pour tripsMap

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
                stopsMap.put(stopId, stop); // Stockage dans stopsMap
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
                routesMap.put(routeId, route); // Stockage dans routesMap
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
                tripsMap.put(tripId, trip); // Stockage dans tripsMap
            }
        }
    }

    /**
     * Lit un fichier CSV et renvoie son contenu sous forme de IList.
     */
    private IList<String> readCsvFile(File file) throws IOException {
        IList<String> content = GamaListFactory.create();
     // Vérifier que l'objet File est bien un fichier
        if (!file.isFile()) {
            throw new IOException(file.getAbsolutePath() + " n'est pas un fichier valide.");
        }
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
