package gama.extension.GTFS.gaml;


import gama.core.common.interfaces.ICreateDelegate;
import gama.core.runtime.IScope;
import gama.core.metamodel.agent.IAgent;
import gama.core.metamodel.population.IPopulation;
import gama.core.util.GamaListFactory;
import gama.core.util.IList;
import gama.extension.GTFS.TransportStop;
import gama.extension.GTFS.GTFS_reader;
import gama.gaml.statements.Arguments;
import gama.gaml.statements.CreateStatement;
import gama.gaml.statements.RemoteSequence;
import gama.gaml.types.IType;
import gama.gaml.types.Types;

import java.util.List;
import java.util.Map;

/**
 * Class responsible for creating agents from GTFS data.
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
     * Determines if this delegate can accept the provided source (expects a folder path).
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
            List<TransportStop> stops = gtfsReader.getStops();

            scope.getGui().getConsole().informConsole("Creating agents from GTFS_reader with " + stops.size() + " stops", scope.getSimulation());

            int limit = max != null ? Math.min(max, stops.size()) : stops.size();

            for (int i = 0; i < limit; i++) {
                TransportStop stop = stops.get(i);
                Map<String, Object> stopInit = Map.of(
                    "stopId", stop.getStopId(),
                    "stopName", stop.getStopName()
                );
                inits.add(stopInit);
                scope.getGui().getConsole().informConsole("Adding TransportStop to inits: " + stop.getStopId(), scope.getSimulation());
            }
            return true;
        }
        return false;
    }


    /**
     * Defines the source type as a file path for GTFS data.
     */
    @Override
    public IType<?> fromFacetType() {
        return Types.FILE; // The source is a GTFS file path (String)
    }
 
    /**
     * Fully handles the creation of agents using the GTFS data.
     */
    @Override
    public IList<? extends IAgent> createAgents(IScope scope, IPopulation<? extends IAgent> population,
                                                List<Map<String, Object>> inits, CreateStatement statement, RemoteSequence sequence) {
        IList<IAgent> createdAgents = GamaListFactory.create();

        for (Map<String, Object> init : inits) {
            IList<? extends IAgent> agents = population.createAgents(scope, 1, List.of(init), false, true);
            IAgent agent = agents.get(0);
            createdAgents.add(agent);
            System.out.println("Agent create with stopId = " + init.get("stopId") + " and stopName = " + init.get("stopName"));
        }

        return createdAgents;
    }

}