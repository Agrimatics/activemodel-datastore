# frozen_string_literal: true

class Recipe
  attr_accessor :amount               # Float
  attr_accessor :name                 # String
  attr_accessor :ingredients          # gives us 'accepts_nested_attributes_for' like functionality

  before_validation :set_default_values, :set_nested_recipe_ids
  after_validation :format_values

  validates :amount, numericality: { greater_than_or_equal_to: 1 }
  validates :name, presence: true
  
  validates :ingredients, presence: true # Recipes must have at least one RecipeContent.
  validates_associated :ingredients

  enable_change_tracking :amount, :name

  def entity_properties
    %w(amount name)
  end

  def set_default_values
    default_property_value :amount, 100.0
  end

  def format_values
    format_property_value :amount, :float
  end

  def ingredients_attributes=(attributes)
    assign_nested_attributes(:ingredients, attributes)
  end

  def build_ingredients
    return unless ingredients.nil? || ingredients.empty?
    self.ingredients = [Ingredient.new(order: 1)]
  end

  def set_ingredient
    content = Ingredient.find_latest(account_id, where: ['recipeId', '=', id])
    content.sort! { |a, b| a.order <=> b.order }
    self.ingredients = content
  end

  private

  ##
  # For each associated Ingredient sets the recipeId to the id of the Recipe.
  #
  def set_nested_recipe_ids
    nested_models.each { |ingredient| ingredient.recipeId = id }
  end
end
