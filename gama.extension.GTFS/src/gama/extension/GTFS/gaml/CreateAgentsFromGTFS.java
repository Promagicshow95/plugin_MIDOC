package gama.extension.GTFS.gaml;

import gama.core.common.interfaces.ICreateDelegate;
import gama.core.runtime.IScope;
import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.IShape;
import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.GamaPair;
import gama.core.util.IList;
import gama.core.util.IMap;
import gama.extension.GTFS.TransportStop;
import gama.extension.GTFS.TransportTrip;
import gama.extension.GTFS.GTFS_reader;
import gama.extension.GTFS.TransportRoute;
import gama.extension.GTFS.TransportShape;
import gama.gaml.expressions.IExpression;
import gama.gaml.operators.Cast;
import gama.gaml.operators.spatial.SpatialCreation;
import gama.gaml.species.ISpecies;
import static gama.core.common.interfaces.IKeyword.SPECIES;
import gama.gaml.statements.Arguments;
import gama.gaml.statements.CreateStatement;
import gama.gaml.statements.RemoteSequence;
import gama.gaml.types.IType;
import gama.gaml.types.Types;

import java.util.HashMap;
import java.util.HashSet;
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

            // Retrieve the species from the statement
            IExpression speciesExpr = statement.getFacet(SPECIES);
            ISpecies targetSpecies = Cast.asSpecies(scope, speciesExpr.value(scope));

            if (targetSpecies == null) {
                scope.getGui().getConsole().informConsole("No species specified in the statement", scope.getSimulation());
                return false;
            }

            // Retrieve the population for the target species
            IPopulation<? extends IAgent> population = scope.getSimulation().getPopulationFor(targetSpecies);

            if (population == null) {
                System.err.println("[ERROR] Population not found for species: " + targetSpecies.getName());
                return false;
            }

            if (targetSpecies.implementsSkill("TransportStopSkill")) {
                List<TransportStop> stops = gtfsReader.getStops();
                if (!stops.isEmpty()) {
                    System.out.println("[LOG] Found " + stops.size() + " stops in GTFS data.");
                    handleStops(scope, inits, stops, max, population);
                } else {
                    scope.getGui().getConsole().informConsole("No stops found in GTFS data.", scope.getSimulation());
                }
            } else if (targetSpecies.implementsSkill("TransportTripSkill")) {
                List<TransportTrip> trips = gtfsReader.getTrips();
                if (!trips.isEmpty()) {
                	 addTripInits(scope, inits, trips, max);
                }
            } else if (targetSpecies.implementsSkill("TransportShapeSkill")) {
                List<TransportShape> shapes = gtfsReader.getShapes();
                if (!shapes.isEmpty()) {
                	 addShapeInits(scope, inits, shapes, max);
                }
            } else {
                scope.getGui().getConsole().informConsole("Unrecognized skill for target species.", scope.getSimulation());
            }

            return true;
        }

        scope.getGui().getConsole().informConsole("The source is not a valid GTFS_reader", scope.getSimulation());
        return false;
    }
    
    
    private void handleStops(IScope scope, List<Map<String, Object>> inits, List<TransportStop> stops, Integer max, IPopulation<? extends IAgent> population) {
        // Étape 1 : Ajouter les initialisations (ne crée pas les agents ici)
        addStopInits(scope, inits, stops, max);

        System.out.println("[LOG] handleStops prepared " + inits.size() + " initializations for TransportStop agents.");
    }



    private boolean isStopAgent(Map<String, Object> init) {
        return init.containsKey("stopId") && init.containsKey("stopName") && init.containsKey("location");
    }

    private boolean isTripAgent(Map<String, Object> init) {
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

    private void addStopInits(IScope scope, List<Map<String, Object>> inits, List<TransportStop> stops, Integer max) {
        int limit = max != null ? Math.min(max, stops.size()) : stops.size();

        for (int i = 0; i < limit; i++) {
            TransportStop stop = stops.get(i);
            Map<String, Object> stopInit = new HashMap<>();
            stopInit.put("stopId", stop.getStopId());
            stopInit.put("stopName", stop.getStopName());
            stopInit.put("location", stop.getLocation());
            stopInit.put("departureTripsInfo", stop.getDepartureTripsInfo());
            stopInit.put("name", stop.getStopName());
            inits.add(stopInit);
        }
    }



    private void addTripInits(IScope scope, List<Map<String, Object>> inits, List<TransportTrip> trips, Integer max) {
        int limit = max != null ? Math.min(max, trips.size()) : trips.size();

        for (int i = 0; i < limit; i++) {
            TransportTrip trip = trips.get(i);

            // Validate TransportTrip data
            if (trip.getTripId() == 0 || trip.getRouteId() == null || trip.getShapeId() == 0 || trip.getStopDetails() == null) {
                System.err.println("[Error] Invalid data for TransportTrip: " + trip);
                continue;
            }

            // Prepare initialization data for the agent
            Map<String, Object> tripInit = new HashMap<>();
            tripInit.put("tripId", trip.getTripId());
            tripInit.put("routeId", trip.getRouteId());
            tripInit.put("serviceId", trip.getServiceId());
            tripInit.put("directionId", trip.getDirectionId());
            tripInit.put("shapeId", trip.getShapeId());

            // Add stops (details) to tripInit
            IList<IMap<String, Object>> stopDetails = trip.getStopDetails();
            tripInit.put("stopDetails", stopDetails);

            // Add destination
            String destination = trip.getDestination();
            tripInit.put("destination", destination);

            // Add initialization to the global list
            inits.add(tripInit);
            System.out.println("[Debug] Initialization added for trip: " + trip.getTripId());
        }
    }

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

    private void addShapeInits(IScope scope, List<Map<String, Object>> inits, List<TransportShape> shapes, Integer max) {
        int limit = max != null ? Math.min(max, shapes.size()) : shapes.size();

        for (int i = 0; i < limit; i++) {
            TransportShape transportShape = shapes.get(i);

            if (transportShape.getShapeId() == 0 || transportShape.getPoints() == null || transportShape.getPoints().isEmpty()) {
                System.err.println("[Error] Invalid data for TransportShape: " + transportShape);
                continue;
            }

            Map<String, Object> shapeInit = new HashMap<>();
            shapeInit.put("shapeId", transportShape.getShapeId());

            try {
                // Convert the list of GamaPoints to IList<IShape>
                IList<IShape> shapePoints = GamaListFactory.create();
                for (GamaPoint point : transportShape.getPoints()) {
                    shapePoints.add(point); // Ajout direct si GamaPoint implémente IShape
                }

                // Create the polyline shape from the list of points
                IShape polyline = SpatialCreation.line(scope, shapePoints);
                shapeInit.put("shape", polyline);

                // Log information about the created shape
                System.out.println("[INFO] Polyline created for Shape ID " + transportShape.getShapeId());
                System.out.println("[DEBUG] Shape WKT: " + polyline.serializeToGaml(false));  // Display shape in WKT format
            } catch (Exception e) {
                System.err.println("[ERROR] Failed to create polyline for shape ID " + transportShape.getShapeId() + ": " + e.getMessage());
                continue;
            }

            inits.add(shapeInit);
            System.out.println("[SUCCESS] Shape with ID " + transportShape.getShapeId() + " added to inits.");
        }
    }



    @Override
    public IType<?> fromFacetType() {
        return Types.FILE; // The source is a GTFS file path
    }
    
    @Override
    public IList<? extends IAgent> createAgents(IScope scope, IPopulation<? extends IAgent> population, List<Map<String, Object>> inits, CreateStatement statement, RemoteSequence sequence) {
        IList<? extends IAgent> createdAgents = population.createAgents(scope, inits.size(), inits, false, true);
        IMap<String, IAgent> stopIdToAgentMap = GamaMapFactory.create(Types.STRING, Types.AGENT);

        for (IAgent agent : createdAgents) {
            String stopId = (String) agent.getAttribute("stopId");
            stopIdToAgentMap.put(stopId, agent);
        }

        for (IAgent agent : createdAgents) {
            IMap<String, IList<GamaPair<IAgent, String>>> departureStopsInfo = GamaMapFactory.create(Types.STRING, Types.LIST);
            IMap<String, IList<GamaPair<String, String>>> departureTripsInfo = (IMap<String, IList<GamaPair<String, String>>>) agent.getAttribute("departureTripsInfo");
            for (Map.Entry<String, IList<GamaPair<String, String>>> entry : departureTripsInfo.entrySet()) {
                IList<GamaPair<IAgent, String>> convertedStops = GamaListFactory.create(Types.PAIR);
                for (GamaPair<String, String> pair : entry.getValue()) {
                    IAgent stopAgent = stopIdToAgentMap.get(pair.first());
                    convertedStops.add(new GamaPair<>(stopAgent, pair.getValue(), Types.AGENT, Types.STRING));

                }
                departureStopsInfo.put(entry.getKey(), convertedStops);
            }
            agent.setAttribute("departureStopsInfo", departureStopsInfo);
            agent.setDirectVarValue(scope, "departureTripsInfo", null);

        }

        return createdAgents;
    }


}