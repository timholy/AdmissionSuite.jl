module AdmissionSuite
# All the code is in the subpackages
# However, to avoid having users need to add each subpackage to their environment,
# load them and and export just the module names
using Admit
using Admit.ODBC
using AdmissionTargets
using AdmitConfiguration

export Admit, AdmissionTargets, AdmitConfiguration, ODBC

end
