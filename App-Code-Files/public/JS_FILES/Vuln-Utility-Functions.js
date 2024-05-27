import {gridApi} from './load-vuln-grid.js';
//Grid-Utility-Functions.js
export const statusMappings = {
  not_a_finding: "Resolved",
  open: "In Progress",
  not_applicable: "Resolved(NA)",
  not_reviewed: "New"
};

export const sideBarConfigs = {
  toolPanels: [
    {
      id: 'columns',
      labelDefault: 'Columns',
      labelKey: 'columns',
      iconKey: 'columns',
      toolPanel: 'agColumnsToolPanel',
      toolPanelParams: {
        suppressRowGroups: true,
        suppressValues: true,
        suppressPivots: true,
        suppressPivotMode: true,
        suppressSideButtons: true,
        suppressColumnFilter: true,
        suppressColumnSelectAll: true,
        suppressColumnExpandAll: true,
      },
    },
    {
      id: 'filters',
      labelDefault: 'Filters',
      labelKey: 'filters',
      iconKey: 'filter',
      toolPanel: 'agFiltersToolPanel',
    }
  ]
};

export const getContextMenuItems = (params) => {
    return [
        {
          name: 'Set Status',
          subMenu: [
            { name: 'New', action: () => updateField(params, 'status', 'not_reviewed') },
            { name: 'In Progress', action: () => updateField(params, 'status', 'open') },
            { name: 'Resolved', action: () => updateField(params, 'status', 'not_a_finding') },
            { name: 'NA', action: () => updateField(params, 'status', 'not_applicable') },
          ],
        },
        {
          name: 'Change AOR',
          subMenu: [
            { name: 'OS', action: () => updateField(params, 'aor', 'OS') },
            { name: 'DBA', action: () => updateField(params, 'aor', 'DBA') },
            { name: 'APP', action: () => updateField(params, 'aor', 'APP') },
          ],
        },
        {
          name: 'Assign to',
          subMenu: [
            { name: 'Cody', action: () => updateField(params, 'assigned_to', 'Cody') },
            { name: 'Shelbi', action: () => updateField(params, 'assigned_to', 'Shelbi') },
            { name: 'Maddi', action: () => updateField(params, 'assigned_to', 'Maddi') },
          ],
        },
        {
          name: 'Add Comment',
          action: () => {
            const comment = prompt("Enter comment:");
            if(comment !== null) updateField(params, 'comment', comment);
          },
        },
        {
          name: 'More Details',
          action: () => {
            const selectedNodes = params.api.getSelectedNodes();
            if (selectedNodes.length === 1) {
                var rowData = selectedNodes[0].data;
                // Populate the modal with data available in the row
                document.getElementById("modal-host-name").textContent = rowData.name || "";
                document.getElementById("modal-ssp").textContent = rowData.ssp || "";
                document.getElementById("modal-stig-name").textContent = rowData.product || "";
                document.getElementById("modal-group-id").textContent = rowData.group_id || "";
                document.getElementById("modal-version").textContent = rowData.rule_version || "";
                document.getElementById("modal-rule-id").textContent = rowData.rule_id || "";
                document.getElementById("modal-description").textContent = rowData.rule_title || "";
                document.getElementById("modal-comments").textContent = rowData.comment || "";
                // For Check Text and Fix Text, fetch from the server
                fetchCheckAndFixText(rowData.vulnerability_id).then(details => {
                  document.getElementById("modal-check-text").innerHTML = details.check_content.replace(/\n/g, "<br>");
                  document.getElementById("modal-fix-text").innerHTML = details.fix_text.replace(/\n/g, "<br>");
                    openModal(); // Open the modal after fetching and populating the details
                }).catch(error => console.error('Error fetching details:', error));
        
            } else {
                alert("Error: multiple rows selected");
            }
        }
        },
        'separator',
        'copy'
      ];
};


function openModal() {
  var modal = document.getElementById("detailsModal");
  modal.style.display = "block";
}

function closeModal() {
  var modal = document.getElementById("detailsModal");
  modal.style.display = "none";
}

// Attach closeModal to the close button
var closeButton = document.querySelector(".close");
closeButton.addEventListener('click', closeModal);

// Close modal when clicking outside of it
window.addEventListener('click', function(event) {
  var container1 = document.getElementById("myGrid"); 
  if (event.target == container1) {
    closeModal();
  }
});

async function fetchCheckAndFixText(vulnerabilityId) {
  // Placeholder: Replace with your actual fetch logic and API endpoint
  const response = await fetch(`/api/vulnerabilityDetails/${vulnerabilityId}`);
  if (!response.ok) throw new Error('Failed to fetch details');
  return response.json();
}

export function statusFilterValueGetter(params) {
  return statusMappings[params.data.status];
}

export function statusCellRenderer(params) {
  return statusMappings[params.value];
}

export const dateComparator = (filterLocalDateAtMidnight, cellValue) => {
    var cellDate = new Date(cellValue);
          // Compare cellDate with filterLocalDateAtMidnight
          if (cellDate < filterLocalDateAtMidnight) {
            return -1;
          } else if (cellDate > filterLocalDateAtMidnight) {
            return 1;
          } else {
            return 0; // dates are equal
          }
};


export const onGridReadyHandler = (params) => {
    const urlParams = new URLSearchParams(window.location.search);
    const sspFilter = urlParams.get('ssp'); // Retrieve SSP filter from URL if exists
    const statusFilter = urlParams.get('vstatus'); // Retrieve Status filter from URL if exists

    const filterModel = {};
    if (sspFilter) { // Apply SSP filter if it exists
        filterModel.ssp = {
            type: 'equals',
            filter: sspFilter
        };
    }
    if (statusFilter) { // Apply Status filter if it exists
      filterModel.status = {
          type: 'notContains',
          filter: statusFilter
      };
  }
    params.api.setFilterModel(filterModel);
};

function sendUpdatesToServer(updatedNodes) {
  if (!Array.isArray(updatedNodes) || updatedNodes.length === 0) {
    console.error('sendUpdatesToServer was called with invalid or empty updatedNodes:', updatedNodes);
    return; // Stop execution of the function
  }

  const updates = updatedNodes.map(update => ({
    asset_id: update.asset_id,
    vulnerability_id: update.vulnerability_id,
    field: update.field,
    value: update.value,
  }));

  console.log("Updates to be sent:", JSON.stringify(updates, null, 2));

  fetch('http://localhost:8000/api/vulnerabilities/update', {
    method: 'PUT',
    headers: {
        'Content-Type': 'application/json',
    },
    body: JSON.stringify(updates),
  })
  .then(response => response.json())
  .then(data => {
    console.log('Success:', data);
    if (data.updatedRows && data.updatedRows.length > 0) {
        // Assuming gridApi is accessible here
        updateGridDataWithUpdatedRows(data.updatedRows);
    }
})
  .catch((error) => {
      console.error('Error:', error);
  });
}

function updateField(params, field, value) {
  const nodesToUpdate = params.api.getSelectedNodes(); // Directly get selected nodes
  const updatedNodes = [];
  
  nodesToUpdate.forEach(node => {
    const data = { ...node.data };
    data[field] = value;

    node.setData(data);
    updatedNodes.push({
      asset_id: node.data.asset_id,
      vulnerability_id: node.data.vulnerability_id,
      field: field,
      value: value, // Send only the updated field and value
    });
  });
  // Send updates to server
  sendUpdatesToServer(updatedNodes);
}



export function updateGridDataWithUpdatedRows(updatedRows) {
  updatedRows.forEach(updatedRow => {
    // Format the resolveddate if it exists in the updatedRow
    if (updatedRow.resolveddate) {
      const date = new Date(updatedRow.resolveddate);
      updatedRow.resolveddate = date.toISOString().split('T')[0]; // Converts to "YYYY-MM-DD" format
    }

    // Check and format the scan_date similarly if it exists and needs formatting
    if (updatedRow.scan_date) {
      const scanDate = new Date(updatedRow.scan_date);
      updatedRow.scan_date = scanDate.toISOString().split('T')[0]; // Converts to "YYYY-MM-DD" format
    }

    gridApi.forEachNode(node => {
      if (node.data.asset_id === updatedRow.asset_id && node.data.vulnerability_id === updatedRow.vulnerability_id) {
        const updatedData = { ...node.data, ...updatedRow };
        node.setData(updatedData);
        gridApi.refreshCells({ rowNodes: [node], force: true });
      }
    });
  });
}


export function onCellContextMenu(params) {
  var rowNode = params.node;
  var alreadySelected = rowNode.isSelected();
  // Select the row if it's not already selected
  if (!alreadySelected) {
      params.api.deselectAll();
      rowNode.setSelected(true, true);
  }
}

document.getElementById('saveViewButton').addEventListener('click', function() {
  const viewName = prompt('Enter the name for the new view:');
  if (viewName) {
      const viewState = {
          columnState: gridApi.getColumnState(),
          filterModel: gridApi.getFilterModel(),
          // Add other states as needed, like sortModel
      };
      // Save the view state to localStorage or a server
      localStorage.setItem(viewName, JSON.stringify(viewState));

      // UI: Add the new view to the select dropdown
      const viewSelect = document.getElementById('viewSelect');
      const option = new Option(viewName, viewName.toLowerCase().replace(/\s+/g, '_'));
      viewSelect.add(option);
      viewSelect.value = option.value; // Select the newly added option
  }
});

document.getElementById('importViewInput').addEventListener('change', function(event) {
  const file = event.target.files[0];
  if (file) {
      const reader = new FileReader();
      reader.onload = function(e) {
          const viewState = JSON.parse(e.target.result);
          gridApi.setColumnState(viewState.columnState);
          gridApi.setFilterModel(viewState.filterModel);
          // Apply other states as needed

          // Update the UI or perform additional actions as necessary
          // For example, adding the imported view to a select dropdown for future reference

          alert('Imported view from: ' + file.name);
      };
      reader.readAsText(file);

      // Reset file input to allow re-importing the same file if needed
      event.target.value = '';
  }
});