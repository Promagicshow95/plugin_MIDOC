package gama.extension.GTFS.gaml;

import gama.core.common.interfaces.ICreateDelegate;
import gama.core.runtime.IScope;
import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.IShape;
import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.IList;
import gama.core.util.IMap;
import gama.extension.GTFS.TransportStop;
import gama.extension.GTFS.TransportTrip;
import gama.extension.GTFS.GTFS_reader;
import gama.extension.GTFS.TransportRoute;
import gama.extension.GTFS.TransportShape;
import gama.gaml.expressions.IExpression;
import gama.gaml.operators.Cast;
import gama.gaml.species.ISpecies;
import static gama.core.common.interfaces.IKeyword.SPECIES;
import gama.gaml.statements.Arguments;
import gama.gaml.statements.CreateStatement;
import gama.gaml.statements.RemoteSequence;
import gama.gaml.types.IType;
import gama.gaml.types.Types;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Class responsible for creating agents from GTFS data (TransportStop and TransportTrip).
 */
public class CreateAgentsFromGTFS implements ICreateDelegate {

    /**
     * Indicates that this delegate handles the complete creation of agents.
     */
    @Override
    public boolean handlesCreation() {
        return true;
    }

    /**
     * Determines if this delegate can accept the provided source (expects a GTFS_reader).
     */
    @Override
    public boolean acceptSource(IScope scope, Object source) {
        boolean isAccepted = source instanceof GTFS_reader;
        if (isAccepted) {
            scope.getGui().getConsole().informConsole("GTFS_reader detected as a valid source", scope.getSimulation());
        } else {
            scope.getGui().getConsole().informConsole("Invalid source type provided to acceptSource", scope.getSimulation());
        }
        return isAccepted;
    }

    @Override
    public boolean createFrom(IScope scope, List<Map<String, Object>> inits, Integer max, Object source, Arguments init, CreateStatement statement) {
        if (source instanceof GTFS_reader) {
            GTFS_reader gtfsReader = (GTFS_reader) source;
            

            // Récupérer l'espèce (species) depuis la déclaration
            IExpression speciesExpr = statement.getFacet(SPECIES);
            ISpecies targetSpecies = Cast.asSpecies(scope, speciesExpr.value(scope));

            if (targetSpecies == null) {
                scope.getGui().getConsole().informConsole("No species specified in the statement", scope.getSimulation());
                return false;
            }

            // Check the implemented skill to decide the type of agents to create
            if (targetSpecies.implementsSkill("TransportStopSkill")) {
                List<TransportStop> stops = gtfsReader.getStops();
                if (!stops.isEmpty()) {
                    addStopInits(scope, inits, stops, max);
                } else {
                    scope.getGui().getConsole().informConsole("No stops found in GTFS data.", scope.getSimulation());
                }
            } else if (targetSpecies.implementsSkill("TransportTripSkill")) {
                List<TransportTrip> trips = gtfsReader.getTrips();
                if (!trips.isEmpty()) {
                    addTripInits(scope, inits, trips, max);
                } else {
                    scope.getGui().getConsole().informConsole("No trips found in GTFS data.", scope.getSimulation());
                }
            } else if (targetSpecies.implementsSkill("TransportShapeSkill")) {
                List<TransportShape> shapes = gtfsReader.getShapes();
                if (!shapes.isEmpty()) {
                    addShapeInits(scope, inits, shapes, max);
                }
            } else if (targetSpecies.implementsSkill("TransportRouteSkill")) {
                List<TransportRoute> routes = gtfsReader.getRoutes();
                if (!routes.isEmpty()) {
                    addRouteInits(scope, inits, routes, max);
                }
            } else {
                scope.getGui().getConsole().informConsole("The species does not implement a recognized skill.", scope.getSimulation());
                return false;
            }

            return true;
        }

        scope.getGui().getConsole().informConsole("The source is not a valid GTFS_reader", scope.getSimulation());
        return false;
    }

    private boolean isStopAgent(Map<String, Object> init) {
        return init.containsKey("stopId") && init.containsKey("stopName") && init.containsKey("location");
    }

    private boolean isTripAgent(Map<String, Object> init) {
        return init.containsKey("tripId") && init.containsKey("routeId") && init.containsKey("shapeId");
    }

    private boolean isShapeAgent(Map<String, Object> init) {
        return init.containsKey("shapeId") && init.containsKey("points");
    }
    
    private boolean isRouteAgent(Map<String, Object> init) {
        return init.containsKey("routeId") && init.containsKey("shortName") 
               && init.containsKey("longName") && init.containsKey("type");
    }
    
    
    /**
     * Adds initialization data for TransportStop agents.
     */
    private void addStopInits(IScope scope, List<Map<String, Object>> inits, List<TransportStop> stops, Integer max) {
        int limit = max != null ? Math.min(max, stops.size()) : stops.size();
        System.out.println("[Debug] Nombre total d'arrêts : " + stops.size() + ", Limite : " + limit);

        for (int i = 0; i < limit; i++) {
            TransportStop stop = stops.get(i);
            System.out.println("[Debug] Traitement de l'arrêt " + (i + 1) + "/" + limit + " : " + stop.getStopId());

            // Vérification des données de base
            GamaPoint location = stop.getLocation();
            if (location == null || stop.getStopId() == null || stop.getStopName() == null) {
                System.err.println("[Error] Données invalides pour l'arrêt : " + stop);
                continue;
            }

            // Création de la map d'initialisation
            Map<String, Object> stopInit = new HashMap<>();
            stopInit.put("stopId", stop.getStopId());
            stopInit.put("stopName", stop.getStopName());
            stopInit.put("location", location);
            System.out.println("[Debug] Informations de base ajoutées pour l'arrêt : " + stop.getStopId());

            // Traitement des tripAssociations
            IMap<Integer, IList<GamaPoint>> associations = GamaMapFactory.create(Types.INT, Types.get(IList.class));
            for (Map.Entry<Integer, IList<TransportStop>> entry : stop.getTripAssociations().entrySet()) {
                Integer tripId = entry.getKey();
                IList<TransportStop> predecessors = entry.getValue();
                System.out.println("[Debug] Traitement des prédécesseurs pour tripId : " + tripId);

                // Transformation des TransportStop en leurs positions (GamaPoint)
                IList<GamaPoint> predecessorLocations = GamaListFactory.create(Types.get(IShape.class));
                for (TransportStop predecessor : predecessors) {
                    if (predecessor != null && predecessor.getLocation() != null) {
                        predecessorLocations.add(predecessor.getLocation());
                    } else {
                        System.err.println("[Warning] Prédécesseur avec données manquantes pour tripId : " + tripId);
                    }
                }
                associations.put(tripId, predecessorLocations);
            }
            stopInit.put("tripAssociations", associations);
            System.out.println("[Debug] Associations ajoutées pour l'arrêt : " + stop.getStopId());

            // Gestion des destinations
            IMap<Integer, String> destinations = GamaMapFactory.create(Types.INT, Types.STRING);
            for (Integer tripId : stop.getTripAssociations().keySet()) {
                String destination = stop.getDestination(tripId);
                if (destination != null) {
                    destinations.put(tripId, destination);
                } else {
                    System.err.println("[Warning] Destination manquante pour tripId : " + tripId);
                }
            }
            stopInit.put("destinations", destinations);
            System.out.println("[Debug] Destinations ajoutées pour l'arrêt : " + stop.getStopId());

            // Ajout à la liste globale d'initialisations
            inits.add(stopInit);
            System.out.println("[Debug] Initialisation ajoutée pour l'arrêt : " + stop.getStopId());
        }

        System.out.println("[Debug] Traitement des arrêts terminé.");
    }


    /**
     * Adds initialization data for TransportTrip agents.
     */
    private void addTripInits(IScope scope, List<Map<String, Object>> inits, List<TransportTrip> trips, Integer max) {
        int limit = max != null ? Math.min(max, trips.size()) : trips.size();

        for (int i = 0; i < limit; i++) {
            TransportTrip trip = trips.get(i);
            if (trip.getTripId() == 0 || trip.getRouteId() == null || trip.getShapeId() == 0) {
                System.err.println("[Error] Invalid data for TransportTrip: " + trip);
                continue;
            }

            Map<String, Object> tripInit = new HashMap<>();
            tripInit.put("tripId", trip.getTripId());
            tripInit.put("routeId", trip.getRouteId());
            tripInit.put("serviceId", trip.getServiceId());
            tripInit.put("directionId", trip.getDirectionId());
            tripInit.put("shapeId", trip.getShapeId());
            tripInit.put("stopsInOrder", trip.getStopsInOrder());
            tripInit.put("destination", trip.getDestination());

            inits.add(tripInit);
        }
    }
    
    /**
     * Adds initialization data for TransportRoute agents.
     */
    private void addRouteInits(IScope scope, List<Map<String, Object>> inits, List<TransportRoute> routes, Integer max) {
        int limit = max != null ? Math.min(max, routes.size()) : routes.size();

        for (int i = 0; i < limit; i++) {
            TransportRoute route = routes.get(i);

            if (route.getRouteId() == null || route.getShortName() == null || route.getLongName() == null) {
                System.err.println("[Error] Invalid data for TransportRoute: " + route);
                continue;
            }

            Map<String, Object> routeInit = new HashMap<>();
            routeInit.put("routeId", route.getRouteId());
            routeInit.put("shortName", route.getShortName());
            routeInit.put("longName", route.getLongName());
            routeInit.put("type", route.getType());

            inits.add(routeInit);
            System.out.println("Route Init Data: " + routeInit);
        }
    }

    
    /**
     * Adds initialization data for TransportShape agents.
     */
    
    private void addShapeInits(IScope scope, List<Map<String, Object>> inits, List<TransportShape> shapes, Integer max) {
        int limit = max != null ? Math.min(max, shapes.size()) : shapes.size();

        for (int i = 0; i < limit; i++) {
            TransportShape shape = shapes.get(i);

            if (shape.getShapeId() == 0 || shape.getPoints() == null || shape.getPoints().isEmpty()) {
                System.err.println("[Error] Invalid data for TransportShape: " + shape);
                continue;
            }

            Map<String, Object> shapeInit = new HashMap<>();
            shapeInit.put("shapeId", shape.getShapeId());
            shapeInit.put("points", shape.getPoints());
            
            try {
                IShape polyline = shape.toPolyline(scope);
                shapeInit.put("polyline", polyline);
            } catch (Exception e) {
                System.err.println("Error creating polyline for shape ID " + shape.getShapeId() + ": " + e.getMessage());
            }

            inits.add(shapeInit);
        }
    }


    /**
     * Defines the source type as a GTFS_reader.
     */
    @Override
    public IType<?> fromFacetType() {
        return Types.FILE; // The source is a GTFS file path
    }

    /**
     * Fully handles the creation of agents using the GTFS data.
     */
    @Override
    public IList<? extends IAgent> createAgents(IScope scope, IPopulation<? extends IAgent> population,
                                                List<Map<String, Object>> inits, CreateStatement statement, RemoteSequence sequence) {
    	
    	System.out.println("[Debug] Populations in scope: " + scope.getRoot().getPopulation());
        IList<IAgent> createdAgents = GamaListFactory.create();

        for (Map<String, Object> init : inits) {
        	
        	System.out.println("[Debug] Data in init before agent creation: " + init);
            System.out.println("Processing init: " + init);

            if (isStopAgent(init)) {
                if (init.get("stopId") == null || init.get("stopName") == null || init.get("location") == null) {
                    System.err.println("[Error] Missing required data for TransportStop in init: " + init);
                    continue;
                }
            } else if (isTripAgent(init)) {
                if (init.get("tripId") == null || init.get("routeId") == null || init.get("shapeId") == null) {
                    System.err.println("[Error] Missing required data for TransportTrip in init: " + init);
                    continue;
                }
            } else if (isShapeAgent(init)) {
                if (init.get("shapeId") == null || init.get("points") == null || ((List<?>) init.get("points")).isEmpty()) {
                    System.err.println("[Error] Missing required data for TransportShape in init: " + init);
                    continue;
                }
            } else if (isRouteAgent(init)) {
                if (init.get("routeId") == null || init.get("shortName") == null || init.get("longName") == null || init.get("type") == null) {
                    System.err.println("[Error] Missing required data for TransportRoute in init: " + init);
                    continue;
                }
            }
            
            else {
                System.err.println("[Error] Unknown agent type in init: " + init);
                continue;
            }

            // Création des agents avec des initialisations valides
            IList<Map<String, Object>> mutableInitList = GamaListFactory.create();
            mutableInitList.add(init);
            System.out.println("[Debug] Creating agent with init: " + mutableInitList);
            
            System.out.println("[Debug] Population: " + population.getName());
            IList<? extends IAgent> agents = population.createAgents(scope, 1, mutableInitList, false, true);

            if (agents.isEmpty()) {
                System.err.println("[Error] Failed to create agent for init: " + init);
                continue;
            }

            IAgent agent = agents.get(0);
            createdAgents.add(agent);

            System.out.println("Created agent: " + agent);
        }

        return createdAgents;
    }
}
