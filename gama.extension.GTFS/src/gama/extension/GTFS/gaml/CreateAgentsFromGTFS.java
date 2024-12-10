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
                    System.out.println("[Debug] Nombre total d'arrêts : " + stops.size());
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
        // Ajoutez ici des vérifications pour le champ stopsInOrder
        return init.containsKey("tripId") 
            && init.containsKey("routeId") 
            && init.containsKey("shapeId")
            && init.containsKey("stopsInOrder");
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

        for (int i = 0; i < limit; i++) {
            TransportStop stop = stops.get(i);
            System.out.println("[Debug] Traitement de l'arrêt : " + stop.getStopId());

            GamaPoint location = stop.getLocation();
            if (location == null || stop.getStopId() == null || stop.getStopName() == null) {
                System.err.println("[Error] Données manquantes pour l'arrêt : stopId = " + stop.getStopId() + 
                                   ", location = " + location + 
                                   ", stopName = " + stop.getStopName());
                continue;
            }

            // Initialisation des données de base
            Map<String, Object> stopInit = new HashMap<>();
            stopInit.put("stopId", stop.getStopId());
            stopInit.put("stopName", stop.getStopName());
            stopInit.put("location", location);

            // Processing departureInfoList
            IList<IList<Object>> departureInfoList = stop.getDepartureInfoList();
            if (departureInfoList.isEmpty()) {
                System.err.println("[Error] departureInfoList is empty for stopId: " + stop.getStopId());
            }

            stopInit.put("departureInfoList", departureInfoList);

            inits.add(stopInit);
        }
    }


    /**
     * Adds initialization data for TransportTrip agents.
     */
    private void addTripInits(IScope scope, List<Map<String, Object>> inits, List<TransportTrip> trips, Integer max) {
        int limit = max != null ? Math.min(max, trips.size()) : trips.size();

        for (int i = 0; i < limit; i++) {
            TransportTrip trip = trips.get(i);

            // Validation des données du TransportTrip
            if (trip.getTripId() == 0 || trip.getRouteId() == null || trip.getShapeId() == 0 || trip.getStopsInOrder() == null) {
                System.err.println("[Error] Invalid data for TransportTrip: " + trip);
                continue;
            }

            // Préparation des données d'initialisation pour l'agent
            Map<String, Object> tripInit = new HashMap<>();
            tripInit.put("tripId", trip.getTripId());
            tripInit.put("routeId", trip.getRouteId());
            tripInit.put("serviceId", trip.getServiceId());
            tripInit.put("directionId", trip.getDirectionId());
            tripInit.put("shapeId", trip.getShapeId());

            // Ajouter les stopsInOrder au tripInit
            IList<String> stopsInOrder = trip.getStopsInOrder();
            tripInit.put("stopsInOrder", stopsInOrder);

            // Ajouter la destination
            String destination = trip.getDestination();
            tripInit.put("destination", destination);

            // Ajout de l'initialisation à la liste globale
            inits.add(tripInit);
            System.out.println("[Debug] Initialisation ajoutée pour le trip: " + trip.getTripId());
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
        IList<IAgent> createdAgents = GamaListFactory.create();

        for (Map<String, Object> init : inits) {
            if (init.get("stopId") != null && init.get("departureInfoList") != null) {
                if (((IList<?>) init.get("departureInfoList")).isEmpty()) {
                    System.err.println("[Error] departureInfoList is empty in init: " + init);
                }
            }

            IList<Map<String, Object>> mutableInitList = GamaListFactory.create();
            mutableInitList.add(init);
            IList<? extends IAgent> agents = population.createAgents(scope, 1, mutableInitList, false, true);

            if (agents.isEmpty()) {
                System.err.println("[Error] Failed to create agent for init: " + init);
                continue;
            }

            createdAgents.add(agents.get(0));
        }

        return createdAgents;
    }

}