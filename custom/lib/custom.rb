# Empty namespace required at boot. ChatwootApp.extensions includes "custom"
# when this directory exists, and prepend_mod_with looks up Custom::SomeClass.
# Leaf code stays under Leaf::. A missing constant is skipped once Custom exists.
module Custom
end
