package gama.extension.GTFS.gaml;

import gama.core.common.interfaces.ICreateDelegate;
import gama.core.runtime.IScope;
import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.IShape;
import gama.core.util.GamaListFactory;
import gama.core.util.IList;
import gama.extension.GTFS.TransportStop;
import gama.extension.GTFS.TransportTrip;
import gama.extension.GTFS.GTFS_reader;
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

            // Vérification des compétences implémentées par l'espèce
            if (targetSpecies.implementsSkill("TransportStopSkill")) {
                // Gestion de la création des arrêts (TransportStop)
                List<TransportStop> stops = gtfsReader.getStops();
                if (!stops.isEmpty()) {
                    scope.getGui().getConsole().informConsole("Creating agents from GTFS_reader with " + stops.size() + " stops", scope.getSimulation());
                    addStopInits(scope, inits, stops, max);
                } else {
                    scope.getGui().getConsole().informConsole("No stops found in GTFS data.", scope.getSimulation());
                }

            } else if (targetSpecies.implementsSkill("TransportTripSkill")) {
                // Gestion de la création des trajets (TransportTrip)
                List<TransportTrip> trips = gtfsReader.getTrips();
                if (!trips.isEmpty()) {
                    scope.getGui().getConsole().informConsole("Creating agents from GTFS_reader with " + trips.size() + " trips", scope.getSimulation());
                    addTripInits(scope, inits, trips, max);
                } else {
                    scope.getGui().getConsole().informConsole("No trips found in GTFS data.", scope.getSimulation());
                }

            } else if (targetSpecies.implementsSkill("TransportShapeSkill")) {
                List<TransportShape> shapes = gtfsReader.getShapes();
                if (!shapes.isEmpty()) {
                    scope.getGui().getConsole().informConsole("Creating agents from GTFS_reader with " + shapes.size() + " shapes", scope.getSimulation());
                    addShapeInits(scope, inits, shapes, max);
                } else {
                    scope.getGui().getConsole().informConsole("No shapes found in GTFS data.", scope.getSimulation());
                }
            }else {
                // Espèce inconnue ou sans compétence correspondante
                scope.getGui().getConsole().informConsole(
                    "The species does not implement a recognized skill (e.g., TransportStopSkill or TransportTripSkill).",
                    scope.getSimulation()
                );
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
    /**
     * Adds initialization data for TransportStop agents.
     */
    private void addStopInits(IScope scope, List<Map<String, Object>> inits, List<TransportStop> stops, Integer max) {
        int limit = max != null ? Math.min(max, stops.size()) : stops.size();

        for (int i = 0; i < limit; i++) {
            TransportStop stop = stops.get(i);

            GamaPoint location = stop.getLocation();
            if (location == null || stop.getStopId() == null || stop.getStopName() == null) {
                System.err.println("[Error] Invalid data for TransportStop: " + stop);
                continue;
            }

            Map<String, Object> stopInit = new HashMap<>();
            stopInit.put("stopId", stop.getStopId());
            stopInit.put("stopName", stop.getStopName());
            stopInit.put("location", location);

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
            if (trip.getTripId() == 0 || trip.getRouteId() == null || trip.getShapeId() == 0) {
                System.err.println("[Error] Invalid data for TransportTrip: " + trip);
                continue;
            }

            Map<String, Object> tripInit = Map.of(
                "tripId", trip.getTripId(),
                "routeId", trip.getRouteId(),
                "serviceId", trip.getServiceId(),
                "directionId", trip.getDirectionId(),
                "shapeId", trip.getShapeId()
            );
            inits.add(tripInit);
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
            } else {
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
