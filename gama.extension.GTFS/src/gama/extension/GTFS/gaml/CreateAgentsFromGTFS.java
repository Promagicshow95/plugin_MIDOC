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
                    // Step 1: Add initializations for stops
                    addStopInits(scope, inits, stops, max);

                    // Step 2: Create agents for stops
                    IList<? extends IAgent> createdAgents = population.createAgents(scope, inits.size(), inits, false, true);

                    // Step 3: Create mapping stopId -> IAgent
                    IMap<String, IAgent> stopIdToAgentMap = GamaMapFactory.create(Types.STRING, Types.AGENT);
                    for (IAgent agent : createdAgents) {
                        String stopId = (String) agent.getAttribute("stopId");
                        if (stopId != null) {
                            stopIdToAgentMap.put(stopId, agent);
                        } else {
                            System.err.println("[ERROR] Created agent does not have a stopId.");
                        }
                    }

                    System.out.println("[CHECK] stopIdToAgentMap created with " + stopIdToAgentMap.size() + " entries.");

                    // Step 4: Update `convertedStops` in `departureTripsInfo` for each stop
                    for (TransportStop stop : stops) {
                        if (!stop.getDepartureTripsInfo().isEmpty()) {
                            System.out.println("[INFO] Updating convertedStops for stopId=" + stop.getStopId());
                            
                            for (Map.Entry<String, IMap<String, Object>> tripEntry : stop.getDepartureTripsInfo().entrySet()) {
                                IMap<String, Object> tripInfo = tripEntry.getValue();

                                // Retrieve orderedStops and create convertedStops
                                IList<IMap<String, String>> orderedStops = (IList<IMap<String, String>>) tripInfo.get("orderedStops");
                                IList<IAgent> convertedStops = GamaListFactory.create();

                                for (IMap<String, String> stopEntry : orderedStops) {
                                    String stopId = stopEntry.get("stopId");
                                    IAgent agent = stopIdToAgentMap.get(stopId);

                                    if (agent != null) {
                                        convertedStops.add(agent);
                                    } else {
                                        System.err.println("[ERROR] No agent found for stopId=" + stopId + " in trip=" + tripEntry.getKey());
                                    }
                                }

                                // Update convertedStops in tripInfo
                                tripInfo.put("convertedStops", convertedStops);
                                System.out.println("[DEBUG] convertedStops updated for trip=" + tripEntry.getKey() 
                                                   + " with " + convertedStops.size() + " entries.");
                            }
                        }
                    }

                    System.out.println("[INFO] convertedStops successfully updated for all stops.");
                } else {
                    scope.getGui().getConsole().informConsole("No stops found in GTFS data.", scope.getSimulation());
                }
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

            // Initialize the main attributes of the stop
            stopInit.put("stopId", stop.getStopId());
            stopInit.put("stopName", stop.getStopName());
            stopInit.put("location", stop.getLocation());

            // Add orderedStops from departureTripsInfo if present
            if (!stop.getDepartureTripsInfo().isEmpty()) {
                stopInit.put("departureTripsInfo", stop.getDepartureTripsInfo());
                System.out.println("[DEBUG] departureTripsInfo for stopId=" + stop.getStopId() + " has " 
                                   + stop.getDepartureTripsInfo().size() + " trips.");
            } else {
                stopInit.put("departureTripsInfo", GamaMapFactory.create(Types.STRING, Types.MAP));
                System.err.println("[ERROR] departureTripsInfo is empty for stopId=" + stop.getStopId());
            }

            // Add the initialization to the inits list
            inits.add(stopInit);

            // Print final details for verification
            System.out.println("[CHECK] stopInit added for stopId=" + stop.getStopId() + ": " + stopInit);
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

    @Override
    public IType<?> fromFacetType() {
        return Types.FILE; // The source is a GTFS file path
    }
}
