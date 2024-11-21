package gama.extension.GTFS.gaml;

import gama.core.common.interfaces.ICreateDelegate;
import gama.core.runtime.IScope;
import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.core.metamodel.shape.GamaPoint;
import gama.core.util.GamaListFactory;
import gama.core.util.IList;
import gama.extension.GTFS.TransportStop;
import gama.extension.GTFS.TransportTrip;
import gama.extension.GTFS.GTFS_reader;
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

            // Handle TransportStop creation
            List<TransportStop> stops = gtfsReader.getStops();
            if (!stops.isEmpty()) {
                scope.getGui().getConsole().informConsole("Creating agents from GTFS_reader with " + stops.size() + " stops", scope.getSimulation());
                addStopInits(scope, inits, stops, max);
            }

            // Handle TransportTrip creation
            List<TransportTrip> trips = gtfsReader.getTrips();
            if (!trips.isEmpty()) {
                scope.getGui().getConsole().informConsole("Creating agents from GTFS_reader with " + trips.size() + " trips", scope.getSimulation());
                addTripInits(scope, inits, trips, max);
            }

            return true;
        }
        return false;
    }

    /**
     * Adds initialization data for TransportStop agents.
     */
    private void addStopInits(IScope scope, List<Map<String, Object>> inits, List<TransportStop> stops, Integer max) {
        int limit = max != null ? Math.min(max, stops.size()) : stops.size();

        for (int i = 0; i < limit; i++) {
            TransportStop stop = stops.get(i);

            // Vérification des données de stop
            GamaPoint location = stop.getLocation();
            if (location == null) {
                System.err.println("[Error] Null location for stopId: " + stop.getStopId());
                continue; // Ne pas ajouter d'initialisation si la localisation est invalide
            }

            // Création d'une carte mutable pour les initialisations
            Map<String, Object> stopInit = new HashMap<>();
            stopInit.put("stopId", stop.getStopId());
            stopInit.put("stopName", stop.getStopName());
            stopInit.put("location", location);

            // Vérification finale des données
            System.out.println("Adding stop init: " + stopInit);

            // Ajout des initialisations
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
            Map<String, Object> tripInit = Map.of(
                "tripId", trip.getTripId(),
                "routeId", trip.getRouteId(),
                "serviceId", trip.getServiceId(),
                "directionId", trip.getDirectionId(),
                "shapeId", trip.getShapeId()
            );
            inits.add(tripInit);
            scope.getGui().getConsole().informConsole("Added TransportTrip to inits: " + trip.getTripId(), scope.getSimulation());
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

            if (init.get("stopId") == null || init.get("stopName") == null || init.get("location") == null) {
                System.err.println("[Error] Missing required data in init: " + init);
                continue; // Ignore les initialisations invalides
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
