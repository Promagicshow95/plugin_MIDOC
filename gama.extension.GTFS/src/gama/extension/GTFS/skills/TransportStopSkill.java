package gama.extension.GTFS.skills;

import gama.extension.GTFS.TransportStop;
import gama.extension.GTFS.GTFS_reader;
import gama.annotations.precompiler.GamlAnnotations.skill;
import gama.annotations.precompiler.GamlAnnotations.vars;
import gama.annotations.precompiler.GamlAnnotations.variable;
import gama.annotations.precompiler.GamlAnnotations.getter;
import gama.annotations.precompiler.GamlAnnotations.setter;
import gama.annotations.precompiler.GamlAnnotations.action;
import gama.annotations.precompiler.GamlAnnotations.arg;
import gama.annotations.precompiler.GamlAnnotations.doc;
import gama.core.metamodel.agent.IAgent;
import gama.core.runtime.IScope;
import gama.core.util.GamaListFactory;
import gama.core.util.IList;
import gama.gaml.skills.Skill;
import gama.gaml.types.IType;
import gama.core.metamodel.population.IPopulation;
import gama.core.metamodel.shape.GamaPoint;

import java.util.List;

/**
 * The skill TransportStopSkill for handling GTFS transport stops in GAMA.
 * This skill allows agents to load and manage public transport stops from GTFS files.
 */
@skill(name = "TransportStopSkill", doc = @doc("Skill for agents that manage public transport stops based on GTFS data. It allows loading GTFS stops and creating corresponding agents."))
@vars({
    @variable(name = "stops", 
        type = IType.LIST, 
        of = IType.AGENT, 
        doc = @doc("List of transport stop agents created from GTFS data.")),
      
})
public class TransportStopSkill extends Skill {

    /**
     * Loads transport stops from a GTFS file and creates agents for each stop.
     * 
     * @param scope The simulation context in GAMA.
     * @param filePath The path to the GTFS file.
     * @return The number of stops successfully loaded.
     */
    @action(name = "loadStopsFromGTFS", args = {
        @arg(name = "filePath", type = IType.STRING, optional = false, doc = @doc("The file path to the GTFS file."))
    }, doc = @doc("Loads transport stops from the specified GTFS file and creates agents for each stop. Returns the number of stops created."))
    public int loadStopsFromGTFS(final IScope scope) {
        String filePath = scope.getStringArg("filePath");
        int stopCount = 0;
        try {
            // Use the GTFS_reader to read GTFS files
            GTFS_reader gtfsReader = new GTFS_reader(scope, filePath);
            List<TransportStop> stops = gtfsReader.getStops();  // Retrieve the list of stops
            
            // Débogage : Affiche le nombre d'arrêts trouvés
            if (scope != null && scope.getGui() != null) {
                scope.getGui().getConsole().informConsole("Nombre d'arrêts trouvés : " + stops.size(), scope.getSimulation());
            } else {
                System.out.println("Nombre d'arrêts trouvés : " + stops.size());
            }

            // Create a list of agents for the stops
            IList<IAgent> stopAgents = GamaListFactory.create();

            // Get the population for the transport stop species
            @SuppressWarnings("unchecked")
			IPopulation<IAgent> stopPopulation = (IPopulation<IAgent>) scope.getSimulation().getPopulationFor("transport_stop_species");

            // For each stop, create an agent with its information
            for (TransportStop stop : stops) {
                double latitude = stop.getLatitude();  // Stop latitude
                double longitude = stop.getLongitude();  // Stop longitude
                GamaPoint location = stop.getLocation(); //Stop location
                String stopId = stop.getStopId();
                String stopName = stop.getStopName();

                // Create an agent for each stop and store it in stopAgents
                IList<IAgent> createdAgents = stopPopulation.createAgents(scope, 1, null, false, true); // Create 1 agent
                IAgent stopAgent = createdAgents.get(0); // Access the created agent
                stopAgent.setAttribute("location", location);
                stopAgent.setAttribute("latitude", latitude);
                stopAgent.setAttribute("longitude", longitude);
                stopAgent.setAttribute("stopId", stopId);
                stopAgent.setAttribute("stopName", stopName);

                stopAgents.add(stopAgent);
                stopCount++; // Increment stop count
            }

            // Update the 'stops' attribute with the list of created agents
            scope.getAgent().setAttribute("stops", stopAgents);

        } catch (Exception e) {
            // Handle exceptions when loading stops from GTFS
            scope.getGui().getConsole().informConsole("Erreur lors du chargement des arrêts depuis GTFS : " + e.getMessage(), scope.getSimulation());
        }

        // Return the number of stops created
        return stopCount;
    }

    // Getter for the list of stops (stops)
    @SuppressWarnings("unchecked")
	@getter("stops")
    public IList<IAgent> getStops(final IAgent agent) {
        return (IList<IAgent>) agent.getAttribute("stops");
    }

    // Setter for the list of stops (stops)
    @setter("stops")
    public void setStops(final IAgent agent, final IList<IAgent> stops) {
        agent.setAttribute("stops", stops);
    }
}
