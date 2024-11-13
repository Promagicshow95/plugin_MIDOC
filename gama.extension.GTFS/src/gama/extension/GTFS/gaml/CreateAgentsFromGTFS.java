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
        return source instanceof GTFS_reader; // Check if the source is a valid GTFS folder path
    }

    /**
     * Fills the initialization map for creating agents from GTFS data.
     */
    @Override
    public boolean createFrom(IScope scope, List<Map<String, Object>> inits, Integer max, Object source, Arguments init,
                              CreateStatement statement) {
    	
        try {
            GTFS_reader gtfsReader = new GTFS_reader(scope, (String) source);
            List<TransportStop> stops = gtfsReader.getStops();

            // Maximum number of agents to create
            int limit = max != null ? Math.min(max, stops.size()) : stops.size();

            for (int i = 0; i < limit; i++) {
                TransportStop stop = stops.get(i);
                Map<String, Object> stopInit = Map.of(
                    "stopId", stop.getStopId(),
                    "stopName", stop.getStopName()
//                  "latitude", stop.getLatitude(),
//                  "longitude", stop.getLongitude()
                );
                inits.add(stopInit); // Add each stop's initial attributes
            }
            return true;
        } catch (Exception e) {
            scope.getGui().getConsole().informConsole("Error while loading GTFS stops: " + e.getMessage(), scope.getSimulation());
            return false;
        }
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
        	
            // Create the agent and set its attributes
        	IList<? extends IAgent> agents = population.createAgents(scope, 1, List.of(init), false, true);
        	IAgent agent = agents.get(0);
        	createdAgents.add(agent); 
        	
        }

        return createdAgents;
    }
}
