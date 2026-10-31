class AddLastGearToVehicles < ActiveRecord::Migration[8.1]
  def change
    add_column :vehicles, :last_gear, :string
  end
end
