class UpdateUserTeslaStatus < ActiveRecord::Migration[8.1]
  def change
    # Remove tesla_id column
    remove_index :users, :tesla_id if index_exists?(:users, :tesla_id)
    remove_column :users, :tesla_id, :string

    # Add status enum: pending (no Tesla connection), started (OAuth complete), verified (Fleet API token obtained)
    add_column :users, :tesla_status, :integer, default: 0, null: false
    add_index :users, :tesla_status
  end
end
