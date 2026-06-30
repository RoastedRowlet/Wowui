local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Monk-Brewmaster','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Rogue-Assassination','Mage-Frost','DeathKnight-Blood','DeathKnight-Frost','Paladin-Retribution','Warrior-Arms','Hunter-BeastMastery','Druid-Balance','Warrior-Protection','Mage-Fire','Druid-Restoration','Paladin-Protection','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Unholy','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Warlock-Demonology','Druid-Guardian','Paladin-Holy','Warlock-Destruction','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Evoker-Preservation','Warlock-Affliction','Mage-Arcane','Monk-Windwalker',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aarztok:BAAALgAECgUJBQABLgAFFAcJFgABAOwZAA==.',
Ac='Achepir:BAAALgADCgIJAgAAAA==.Achiella:BAAALgAECgEJAQAAAA==.',
Ad='Advisor:BAACLgAFFH8KAAICAAQJkRBeQADjAAACAAQJkRBeQADjAAAuAAQKfzQAAwIACQmcJG0JAOECAAIACQmcJG0JAOECAAMAAQl5F2+ZAEQAAAAA.',
Ae='Aería:BAAALgAECgYJDwAAAA==.',
Ah='Ahnkho:BAAALgAECgEJAQAAAA==.',
Ai='Ailea:BAAALgAECgMJAwAAAA==.Aindie:BAAALgADCgEJAQAAAA==.',
Ak='Akarm:BAAALgAECgEJAQAAAA==.',
Al='Alcomancer:BAAALgADCgIJAgAAAA==.Aldoraine:BAAALgAECgEJAgABLgAECgEJAgAEAAAAAA==.Aleks:BAAALgAECgQJBAAAAA==.Altrix:BAAALgAECgUJBgABLgAFFAMJBQAFABkDAA==.Aluna:BAAALgAECgcJEAAAAA==.Alvarr:BAAALgADCgcJEAAAAA==.',
Am='Amalia:BAAALgADCgEJAQAAAA==.Amandakk:BAAALgAECgQJCAAAAA==.Aminas:BAAALgAECgEJAQAAAA==.',
An='Andolas:BAAALgADCgYJCQAAAA==.Angelicuss:BAAALgAECgUJBgABLgAECgkJSQAGAL8jAA==.Annya:BAAALgAECgcJCAAAAA==.Antheria:BAAALgADCgMJAwAAAA==.',
Ap='Aparajita:BAAALgAECgEJAwABLgABCgMJAwAEAAAAAA==.Aphrodite:BAAALgAECgYJEAAAAA==.',
Ar='Archie:BAAALgAECgQJBgAAAA==.Arendt:BAAALgADCgQJCwAAAA==.Aristoleh:BAAALgAECgIJAgABLgAFFAcJFAADANgOAA==.Arkahera:BAAALgAECgQJBQABLgAFFAcJFgABAOwZAA==.Aroara:BAAALgAECgEJAQAAAA==.Arolder:BAABLgAECn8mAAMHAAkJqyGABgC4AgAHAAkJdSGABgC4AgAIAAcJZB3dAwA6AgAAAA==.Arredin:BAAALgADCgYJBgAAAA==.Arturium:BAAALgAECgUJBQAAAA==.',
As='Astayuno:BAAALgAECgQJBAAAAA==.',
At='Atabey:BAABLgAECn87AAIJAAkJICIvEQDeAgAJAAkJICIvEQDeAgABLgABCgMJAwAEAAAAAA==.Atimusk:BAAALgADCggJDwABLgAECgYJCgAEAAAAAA==.Atoadaso:BAABLgAECn8ZAAIKAAgJABifAADqAQAKAAgJABifAADqAQAAAA==.Atretes:BAAALgAECgUJBQAAAA==.Attretes:BAAALgADCgcJDwAAAA==.',
Az='Azazél:BAAALgAECgEJAQABLgAFFAQJEQAGAJ0LAA==.Azcowboy:BAAALgAECgUJEAAAAA==.Azezel:BAAALgADCgYJBgAAAA==.Aznå:BAAALgAECggJCgAAAA==.',
Ba='Badco:BAAALgAECgQJBAAAAA==.Bairne:BAAALgADCgcJBwAAAA==.Balacheck:BAABLgAECn8jAAILAAgJGAdKFACUAAALAAgJGAdKFACUAAAAAA==.Bang:BAAALgADCgEJAQAAAA==.Barecub:BAAALgAECgEJAQAAAA==.Barton:BAAALgADCgcJCQAAAA==.Baultenaz:BAAALgADCgQJBAAAAA==.',
Bb='Bbite:BAABLgAECn8sAAIMAAkJbxxeDACQAgAMAAkJbxxeDACQAgAAAA==.',
Be='Beanwater:BAAALgAECgMJAwAAAA==.Belmax:BAAALgADCgYJFAAAAA==.Bemon:BAAALgADCgcJBwABLgAECgcJFAAGAKAcAA==.',
Bi='Bigbadwoof:BAAALgAECgEJAgAAAA==.Bighog:BAACLgAFFH8UAAINAAQJGyHPDQBSAQANAAQJGyHPDQBSAQAuAAQKfxgAAw0ABwloJmkHAI0CAA0ABwloJmkHAI0CAAoAAgkZFB5UAIUAAAAA.Bipbipbup:BAAALgAECgEJAQAAAA==.',
Bj='Björn:BAAALgADCgcJBwAAAA==.',
Bl='Blaazzin:BAAALgAECgMJAwAAAA==.Blessa:BAAALgADCgkJCQAAAA==.Blinck:BAAALgAECgUJCAAAAA==.Blinkz:BAAALgAECgUJBQAAAA==.Bloomzy:BAACLgAFFH8MAAIGAAMJFiGBHgDgAAAGAAMJFiGBHgDgAAAuAAQKfy4AAwYACQluGoc1AEMCAAYACQluGoc1AEMCAA4AAgl6G1oKAJ8AAAAA.Blytzbrigade:BAAALgADCgkJDQAAAA==.',
Bo='Boneycheese:BAABLgAFFH8FAAIFAAMJGQM/CQC1AAAFAAMJGQM/CQC1AAAAAA==.Boombástic:BAABLgAECn8oAAMMAAkJaQ8rLQBwAQAMAAgJMhArLQBwAQAPAAIJ0A/fpgBlAAAAAA==.Boomco:BAABLgAECn8dAAILAAgJOBGRUwCoAQALAAgJOBGRUwCoAQAAAA==.Boomtothekin:BAAALgAECgIJAgABLgAFFAMJCwAJALQTAA==.Bootes:BAAALgAECgMJAwAAAA==.Bors:BAAALgADCggJEAAAAA==.Boulderholdr:BAAALgAECgYJEgAAAA==.Boxing:BAAALgADCgIJAgAAAA==.',
Br='Bravillius:BAAALgAECgYJBgAAAA==.Breaddy:BAAALgAECgYJCwAAAA==.Breeti:BAABLgAECn8UAAIQAAgJNg00JADzAAAQAAgJNg00JADzAAAAAA==.Broin:BAAALgAECgEJAQAAAA==.Bronte:BAABLgAECn8cAAIQAAkJyRmeCgAkAgAQAAkJyRmeCgAkAgAAAA==.Bryda:BAAALgAECgQJCwAAAA==.',
Bu='Bubblez:BAAALgAECggJCQAAAA==.Burblingbee:BAAALgADCgcJBwAAAA==.',
Bw='Bwucewee:BAABLgAECn8WAAIBAAYJbA2vUAC/AAABAAYJbA2vUAC/AAAAAA==.',
Ca='Cajbo:BAABLgAECn89AAIFAAkJViHdAQDbAgAFAAkJViHdAQDbAgAAAA==.Calyssa:BAABLgAECn8eAAIJAAgJ6w5AjQBXAQAJAAgJ6w5AjQBXAQAAAA==.Candyflöss:BAACLgAFFH8JAAINAAQJbBxHEwALAQANAAQJbBxHEwALAQAuAAQKfyEAAw0ABwmTIsMOAP8BAA0ABwmTIsMOAP8BAAoAAQkLEER5ADAAAAAA.Capmkrunch:BAAALgAECgEJAwABLgAECggJEgAEAAAAAA==.Caraling:BAAALgAECgMJBgAAAA==.Caralynn:BAAALgAECgUJEAAAAA==.Carpe:BAAALgAECgYJBgAAAA==.Cartan:BAACLgAFFH8HAAIRAAQJJhTfLwD3AAARAAQJJhTfLwD3AAAuAAQKf0QAAhEACQkbIdAFAEoDABEACQkbIdAFAEoDAAAA.Castisteus:BAAALgAECgYJCAAAAA==.Cathelina:BAAALgADCggJFQAAAA==.Cathom:BAAALgAECgUJCgAAAA==.',
Ch='Charcasm:BAAALgAECgYJCAAAAA==.Charizaard:BAAALgAECgYJCQAAAA==.Charizaardx:BAACLgAFFH8TAAMSAAYJFgqFAQDCAAATAAUJqwPWNQDsAAASAAQJGw+FAQDCAAAuAAQKf0oAAxIACQkBGzMEADgCABIACQk3GjMEADgCABMACAnRFPYlAI0BAAAA.Chevytron:BAAALgAECgYJEwAAAA==.Chune:BAAALgADCgcJDAAAAA==.',
Ci='Cinder:BAAALgADCgIJAgAAAA==.',
Cl='Clement:BAAALgAECgQJBAAAAA==.Cletus:BAABLgAECn8fAAMUAAgJEg99XgDaAAAUAAYJYQ99XgDaAAANAAQJiQu2BQBtAAAAAA==.Clives:BAAALgAECgEJAQAAAA==.Clmx:BAAALgADCgIJAgAAAA==.Clément:BAAALgADCgUJBgAAAA==.',
Co='Coffeebeans:BAABLgAECn8iAAMPAAgJExbjPgCnAQAPAAcJfxTjPgCnAQAMAAgJwAt9NgA8AQAAAA==.Cowabunga:BAAALgADCgIJAgAAAA==.Cowdeath:BAAALgAECgEJAQAAAA==.Cowkiller:BAAALgADCgIJAgAAAA==.',
Cr='Crazyasian:BAAALgAECgYJDgAAAA==.Creslan:BAAALgAECgYJBgABLgAECgkJXAAVACsfAA==.Crimsonthot:BAAALgAECggJDQAAAA==.Crogan:BAABLgAECn8VAAQWAAkJzAgNNgApAQAWAAgJJwkNNgApAQAXAAYJcQiHXAClAAAYAAEJ+gVAWgAuAAAAAA==.Crysiscane:BAAALgADCgYJBQAAAA==.',
Ct='Ctrlaltdk:BAAALgAECgEJAQABLgAECggJEgAEAAAAAA==.',
Cy='Cybrocookie:BAAALgADCgEJAQAAAA==.Cyrberus:BAAALgAECgUJBwAAAA==.',
['Cá']='Cáposhady:BAAALgAECgEJAQAAAA==.',
Da='Dagda:BAAALgAECgYJBwAAAA==.Dagul:BAAALgAECgcJCwAAAA==.Dahgrimza:BAAALgAECgUJBQABLgAECgUJCQAEAAAAAA==.Dalna:BAABLgAECn86AAIRAAkJTBnJEgCHAgARAAkJTBnJEgCHAgAAAA==.Danilex:BAABLgAECn8cAAIGAAgJCx9pSABeAgAGAAgJCx9pSABeAgABLgAFFAkJNQAYAOIYAA==.Danksoul:BAAALgAECgkJAQABLgAECgkJCAAEAAAAAA==.Darat:BAAALgADCgEJAQAAAA==.Darcorin:BAABLgAECn8fAAIZAAgJIBbfcACDAQAZAAgJIBbfcACDAQAAAA==.Darkblitz:BAAALgADCgQJBQAAAA==.Darklürker:BAABLgAECn8fAAILAAgJDAvlCQAdAQALAAgJDAvlCQAdAQAAAA==.Darksaber:BAABLgAECn8VAAIMAAUJlQs7WgCqAAAMAAUJlQs7WgCqAAAAAA==.Dasthodan:BAAALgAECgYJCQAAAA==.Dayne:BAAALgAECgcJDQAAAA==.',
Dc='Dctrpepper:BAAALgAECgIJAgAAAA==.',
De='Deathcore:BAAALgADCgkJEwAAAA==.Deathminions:BAAALgADCgUJBQAAAA==.Deathtardza:BAAALgAECgQJBwAAAA==.Deathwish:BAAALgADCgIJAgAAAA==.Decklan:BAAALgADCgEJAQAAAA==.Decorum:BAAALgADCgEJAQAAAA==.Defiant:BAAALgADCgEJAQAAAA==.Deilliann:BAABLgAECn8xAAQMAAkJJQQPRgD0AAAMAAkJJQQPRgD0AAAPAAkJHAYWbQDtAAAaAAIJhQCIOgAdAAAAAA==.Deldawalth:BAAALgADCgcJEgAAAA==.Delvisprezly:BAAALgAECggJEgAAAA==.Demonica:BAABLgAECn8yAAQbAAkJyglaAQAhAQAbAAkJsghaAQAhAQAcAAUJ4gYqRADmAAAdAAIJwwxf8QBdAAAAAA==.Demonky:BAAALgAECgIJAgAAAA==.Demonology:BAAALgADCgYJBwAAAA==.Denastus:BAAALgAECgUJBQAAAA==.Dethknyght:BAAALgAECgkJCgABLgAFFAcJFgABAOwZAA==.Detoxin:BAAALgAECgIJAgAAAA==.Devick:BAAALgAECgEJAQAAAA==.',
Di='Dinta:BAABLgAECn9VAAIJAAkJnxxGHACbAgAJAAkJnxxGHACbAgAAAA==.Dionysys:BAAALgAECgEJAgABLgABCgMJAwAEAAAAAA==.Dip:BAAALgADCgcJBwAAAA==.',
Dj='Djabuty:BAAALgAECgEJAgAAAA==.',
Do='Dominoes:BAABLgAECn8dAAILAAgJLRuAKwAvAgALAAgJLRuAKwAvAgAAAA==.Domìnion:BAAALgADCgkJEAAAAA==.Dorcater:BAAALgADCgEJAQAAAA==.',
Dr='Dradmaster:BAAALgAECgMJAwAAAA==.Drakth:BAAALgADCgIJAQAAAA==.Drekker:BAABLgAECn8fAAIBAAkJLhX1FgDyAQABAAkJLhX1FgDyAQAAAA==.Drhofmann:BAAALgAECgMJCQAAAA==.',
Du='Duffar:BAABLgAECn8sAAIeAAkJTg0oGgDOAQAeAAkJTg0oGgDOAQAAAA==.Dummblond:BAACLgAFFH8UAAMPAAQJIQ92CQDnAAAPAAQJIQ92CQDnAAAMAAIJMwU9RQBiAAAuAAQKfyQAAw8ACQkwEYE7AKYBAA8ACQkwEYE7AKYBAAwACAmXC+sFAL8AAAAA.Dumptruck:BAAALgAECgYJCQAAAA==.Durgledore:BAABLgAECn8XAAIfAAcJKB0vUgClAQAfAAcJKB0vUgClAQAAAA==.',
Dy='Dyonesa:BAAALgAECgUJBQAAAA==.Dysfunction:BAABLgAECn8XAAIgAAkJeRBfHgBaAQAgAAkJeRBfHgBaAQAAAA==.',
Ea='Earthshield:BAAALgAECgcJDgABLgAFFAIJBQAJAGkHAA==.',
Eg='Ego:BAABLgAECn8iAAIhAAkJPyLXBQAyAwAhAAkJPyLXBQAyAwAAAA==.',
El='Elipto:BAAALgAECgYJBgAAAA==.Ellaana:BAAALgAECgUJEAAAAA==.Elotarra:BAAALgAECgEJAQAAAA==.Elowentinsel:BAAALgAECgEJAQAAAA==.Elsiais:BAAALgADCgUJCwAAAA==.Elvarang:BAAALgAECgMJAwAAAA==.',
En='Enduran:BAAALgAECgYJDQAAAA==.',
Er='Erasi:BAABLgAECn8zAAMXAAkJVApXLQBtAQAXAAkJVApXLQBtAQAWAAUJzwJXXgBhAAAAAA==.',
Es='Es:BAABLgAECn8UAAIZAAcJ8wTGpgA0AQAZAAcJ8wTGpgA0AQAAAA==.Escanorlion:BAAALgADCgcJBwAAAA==.Esileda:BAAALgAECgQJBAAAAA==.Esttsumi:BAAALgAECgkJDwAAAA==.',
Eu='Euphia:BAAALgAECgUJDAAAAA==.',
Ex='Exiled:BAAALgADCgYJCQAAAA==.Exine:BAABLgAECn8uAAILAAkJzxBcDADyAAALAAkJzxBcDADyAAAAAA==.Exodiá:BAAALgAECgYJCwAAAA==.',
Ey='Eyebee:BAAALgADCgEJAQAAAA==.',
Fa='Faeonia:BAABLgAECn8uAAIJAAkJVB1ZIQCBAgAJAAkJVB1ZIQCBAgAAAA==.Faethe:BAAALgAECgEJAgABLgAECgkJSQAGAL8jAA==.Faithfulpain:BAAALgADCgYJBgAAAA==.Farawaystare:BAAALgAECgQJBAAAAA==.Farmerpolly:BAAALgADCgYJCQAAAA==.Farwolf:BAABLgAECn8oAAILAAgJWAoVdgBTAQALAAgJWAoVdgBTAQAAAA==.Fayore:BAAALgADCgcJBwAAAA==.',
Fe='Fearmaxxing:BAAALgAECggJBwABLgAFFAMJCwAZAGgXAA==.Fee:BAACLgAFFH8hAAIJAAYJSR/TBACnAQAJAAYJSR/TBACnAQAuAAQKfz4AAgkACQkUJVYIACgDAAkACQkUJVYIACgDAAAA.Fellyn:BAAALgAECgQJBQAAAA==.Feloniusmunk:BAAALgADCgQJCgAAAA==.Fenrith:BAAALgAECgMJAwAAAA==.Festerr:BAAALgADCgQJAQAAAA==.Feyt:BAAALgADCgMJAwAAAA==.',
Fi='Fidelis:BAAALgADCgYJBgAAAA==.Figaro:BAAALgAECgcJEwAAAA==.Filthy:BAAALgAECgQJBQAAAA==.Fishstick:BAAALgAECgkJDQAAAA==.',
Fl='Flameheart:BAABLgAECn8eAAMiAAgJ5QuFEwAVAQAiAAgJ5QuFEwAVAQAfAAEJAALtaAEPAAAAAA==.Fleathulhu:BAACLgAFFH8OAAIWAAMJAhe4CACbAAAWAAMJAhe4CACbAAAuAAQKfzQAAhYACQn0HV4HAPkCABYACQn0HV4HAPkCAAAA.Flungpu:BAAALgADCgkJFwABLgAECgkJOgALANsSAA==.',
Fo='Foleigh:BAAALgADCggJCwAAAA==.Fostock:BAABLgAECn8sAAMfAAgJrhBNBABPAQAfAAgJrhBNBABPAQAiAAEJvRI0PgA0AAAAAA==.Foxieshoxie:BAAALgAECgEJAwAAAA==.Foxylocksy:BAAALgAECgQJBAAAAA==.',
Fr='Freeman:BAAALgAECgkJCwAAAA==.Frontierland:BAAALgADCgcJDQAAAA==.Frostdoom:BAAALgAECgQJBAAAAA==.Frostmoon:BAAALgADCgIJAgAAAA==.Frozty:BAAALgAECgUJBQAAAA==.',
Fu='Furgy:BAAALgAECgEJAQAAAA==.Furrfoxsake:BAAALgAECgYJDAABLgAECggJDwAeAJcbAA==.Fuzball:BAAALgADCgEJAQAAAA==.Fuzzie:BAAALgADCgYJBAAAAA==.',
Ga='Galfure:BAAALgADCgYJBgAAAA==.Gankuskhan:BAAALgAECgQJBAAAAA==.Ganlolf:BAAALgAECgQJBAABLgAECgQJBQAEAAAAAA==.Ganook:BAAALgADCgkJCgAAAA==.Garwynn:BAABLgAECn83AAIFAAkJhRZmBgACAgAFAAkJhRZmBgACAgAAAA==.',
Ge='Genovefa:BAAALgAECgIJAgAAAA==.',
Gh='Ghoulmaxing:BAABLgAFFH8LAAIZAAMJaBe8HQDwAAAZAAMJaBe8HQDwAAAAAA==.Ghøulish:BAAALgAECgUJBwABLgAECggJMQAPAFwMAA==.',
Gi='Gimper:BAAALgADCgcJFwAAAA==.',
Gl='Glaistia:BAAALgAECgEJAQAAAA==.Glen:BAAALgAECgUJEAAAAA==.Glowstik:BAAALgAECgQJBAAAAA==.',
Go='Goldengraham:BAAALgADCgcJCQAAAA==.Gorgutz:BAAALgADCgEJAQAAAA==.Gormlaîth:BAAALgAECgQJBwABLgAECgYJCgAEAAAAAA==.',
Gr='Grabmymelonz:BAAALgAECgUJBQAAAA==.Graeman:BAAALgADCgMJAwAAAA==.Grandpaslay:BAAALgAECgQJCQAAAA==.Greatpàw:BAAALgAECgEJAQAAAA==.Grisly:BAAALgADCgUJBQAAAA==.',
Gu='Gurrney:BAAALgADCgYJBgAAAA==.',
Gw='Gwyn:BAAALgADCgQJBAAAAA==.',
['Gæ']='Gætherr:BAAALgAECgQJBQAAAA==.',
Ha='Habbyb:BAAALgAECgYJEQAAAA==.Habbypallie:BAAALgADCgYJFAAAAA==.Haimanist:BAABLgAECn8ZAAIQAAgJliAlAwDwAgAQAAgJliAlAwDwAgABLgAFFAcJFgABAOwZAA==.Halixan:BAABLgAECn8gAAIjAAkJWyPxAgDiAgAjAAkJWyPxAgDiAgAAAA==.Handlebardoc:BAACLgAFFH8RAAIZAAQJtRrPFQAhAQAZAAQJtRrPFQAhAQAuAAQKf0AAAhkACQleIoISANoCABkACQleIoISANoCAAAA.Harmoni:BAAALgAECgQJBQABLgAECgkJSQAGAL8jAA==.Hatorade:BAAALgAECgUJBQAAAA==.',
He='Healmemommy:BAAALgAECgYJCgAAAA==.Healsrus:BAAALgAECgkJBQAAAA==.Healze:BAAALgADCgUJBgAAAA==.Hemorrvoid:BAAALgAECgMJBQAAAA==.Heyei:BAAALgAECgUJBgAAAA==.',
Hi='Highroller:BAAALgADCgkJEQAAAA==.',
Ho='Holyname:BAAALgAECgQJAwAAAA==.Holysim:BAAALgAECgEJAQAAAA==.Honir:BAAALgAECgcJDQAAAA==.',
Hu='Hunteð:BAAALgAECgEJAgAAAA==.',
Hy='Hydrozortek:BAAALgAECgEJAQAAAA==.',
Ia='Iamlegend:BAAALgADCgcJBwAAAA==.',
Ib='Iblis:BAAALgADCgcJEgAAAA==.',
Ig='Ignivoid:BAAALgADCggJCAAAAA==.',
Ij='Ijillien:BAAALgAECgIJAgAAAA==.',
Im='Imahaa:BAAALgADCgMJAwAAAA==.Imonster:BAABLgAECn8yAAMiAAkJHwwvFgD2AAAfAAkJ0AjMcQBWAQAiAAYJGw4vFgD2AAAAAA==.',
Ir='Ireus:BAAALgAECgIJAgAAAA==.Ironfizt:BAAALgAECggJDwABLgAECgkJKAAkAIgYAA==.',
Is='Islet:BAAALgAECgEJAQAAAA==.Istia:BAAALgADCgUJBQAAAA==.',
It='Itsgotime:BAAALgAECgMJBgAAAA==.',
Iu='Iudex:BAAALgAECggJEAAAAA==.Iutu:BAAALgAECgUJBQAAAA==.',
Ja='Jaaru:BAAALgADCggJEwAAAA==.Jaayycee:BAAALgAECgMJAwAAAA==.Jamus:BAACLgAFFH8FAAMJAAIJaQcNJgCCAAAJAAIJaQcNJgCCAAAhAAIJsg1yPgBnAAAuAAQKfz8AAyEACQk3JEUCAFgDACEACQk3JEUCAFgDAAkACAlFD6CEAGYBAAAA.Jarvy:BAAALgAECggJCAAAAA==.',
Je='Jedavon:BAAALgAECgEJAQAAAA==.Jenhadin:BAAALgAECgcJCwAAAA==.Jerreden:BAAALgADCgYJBgAAAA==.Jerriden:BAAALgADCgUJCAAAAA==.Jestic:BAABLgAECn8sAAIkAAkJJBUOAQDLAQAkAAkJJBUOAQDLAQAAAA==.',
Ji='Jiangshi:BAAALgAECgYJCgAAAA==.Jilibean:BAAALgADCgIJAgAAAA==.',
Jo='Jons:BAAALgADCgYJEQAAAA==.Joé:BAAALgADCgEJAQAAAA==.',
Ju='Justpwnedu:BAAALgAECgkJCgAAAA==.',
Ka='Kaazel:BAABLgAECn86AAILAAkJ2xL9BQB1AQALAAkJ2xL9BQB1AQAAAA==.Kacee:BAAALgAECgQJBgAAAA==.Kaldor:BAAALgAECgYJEgAAAA==.Kalispo:BAAALgAECgEJAgAAAA==.Kallias:BAAALgAECggJDQAAAA==.Kamsham:BAAALgAECgQJBgABLgAECgkJKQABACUYAA==.Kandiquake:BAAALgAECgIJAgAAAA==.Karea:BAAALgAECgcJDgAAAA==.Karite:BAABLgAECn80AAIlAAkJ/iKCAQDgAgAlAAkJ/iKCAQDgAgAAAA==.Karom:BAAALgADCgMJAwAAAA==.Karsh:BAABLgAECn8mAAIRAAgJRxnIHgAjAgARAAgJRxnIHgAjAgAAAA==.Karveila:BAAALgAECgQJBAAAAA==.Katyla:BAAALgADCgQJBAABLgAECgkJMwALAOoMAA==.Kazar:BAAALgADCgcJDwAAAA==.Kazenoth:BAABLgAECn8rAAMTAAkJxxreFwAYAgATAAkJxxreFwAYAgAmAAEJbxFuPAAyAAAAAA==.',
Ke='Kellement:BAAALgAECgUJBQAAAA==.Ken:BAABLgAECn8bAAIMAAgJVBbYHADiAQAMAAgJVBbYHADiAQABLgAECgkJSgAfADQbAA==.Kennychaoss:BAABLgAECn8xAAMCAAkJzR2hDQDpAgACAAkJzR2hDQDpAgADAAcJZw37RwAUAQAAAA==.Kennykaos:BAAALgAECgQJBwAAAA==.',
Kh='Khrisbkreme:BAAALgAECgEJAQABLgAECggJEgAEAAAAAA==.',
Ki='Kille:BAABLgAECn8eAAILAAgJxhd1OAD8AQALAAgJxhd1OAD8AQAAAA==.',
Kn='Knucks:BAAALgADCgYJBgAAAA==.',
Ko='Kobebrÿant:BAAALgAECgYJDAAAAA==.Kobeqt:BAAALgAECgYJCQAAAA==.Koland:BAAALgADCgkJGAAAAA==.Koomgak:BAAALgAECgIJAwAAAA==.Kosseluna:BAABLgAECn84AAIMAAkJXA4hJwCVAQAMAAkJXA4hJwCVAQAAAA==.Kostazu:BAABLgAECn9WAAIDAAkJuhKBIgDQAQADAAkJuhKBIgDQAQAAAA==.Kozanat:BAAALgADCgEJAQAAAA==.Kozzy:BAAALgADCgUJBQABLgAFFAYJIQAJAEkfAA==.',
Ku='Kulthulhu:BAAALgADCgcJBwABLgAFFAMJDgAWAAIXAA==.Kushcoma:BAAALgAECgYJCQAAAA==.',
Kv='Kvn:BAAALgADCgYJCQAAAA==.',
Ky='Kynvana:BAAALgADCgcJDQAAAA==.',
['Kí']='Kíns:BAAALgAECgEJAgABLgAECgMJBgAEAAAAAA==.',
La='Laity:BAABLgAECn9VAAIJAAkJEyGoCgARAwAJAAkJEyGoCgARAwAAAA==.Lanfer:BAAALgADCgcJGgAAAA==.Laraithe:BAAALgADCgEJAQAAAA==.Larethar:BAAALgADCggJBwAAAA==.Laurentos:BAAALgAECgEJAQAAAA==.Lazraar:BAAALgAECgEJAQAAAA==.Lazylaz:BAABLgAECn8vAAIaAAkJNyQ5AgAKAwAaAAkJNyQ5AgAKAwABLgAFFAgJIgAZAAEeAA==.Lazyriver:BAAALgAECgcJEwAAAA==.',
Le='Lebigmu:BAABLgAECn9CAAIjAAgJmSJQAABzAgAjAAgJmSJQAABzAgAAAA==.Lebleb:BAAALgADCggJCQAAAA==.Leeanna:BAAALgAECgUJCQAAAA==.Lexý:BAAALgAECgEJAQAAAA==.',
Li='Lieff:BAABLgAECn8rAAMcAAgJLhfcIgBhAQAcAAYJUxjcIgBhAQAdAAgJaA4ZbABMAQAAAA==.Lifebloom:BAAALgAECgIJAgABLgAFFAIJBQAJAGkHAA==.Lilctown:BAAALgADCgcJDQAAAA==.Liliyn:BAAALgAECgcJEAABLgAFFAMJCQAeACMhAA==.Lilsoulz:BAAALgADCgUJCQAAAA==.Lindwych:BAAALgADCgYJBgAAAA==.Lisettar:BAABLgAECn8zAAILAAkJ6gyKVACmAQALAAkJ6gyKVACmAQAAAA==.Livedcargox:BAAALgAECgYJBgAAAA==.',
Lo='Lockvegas:BAAALgAECgIJBAAAAA==.Loqir:BAAALgAFFAIJAwABLgAFFAcJHAATAE8aAA==.Lorindis:BAAALgAECgIJAwAAAA==.',
Lu='Luciferser:BAAALgAECgEJAQAAAA==.Luminara:BAAALgADCgMJAwAAAA==.Lunariss:BAAALgADCgUJBQABLgAECgYJBwAEAAAAAA==.Luthbruk:BAAALgADCgYJBgAAAA==.Luxsaria:BAAALgAECgEJAQAAAA==.',
Ly='Lycanbyte:BAABLgAECn8WAAIFAAYJGwX8AQCLAAAFAAYJGwX8AQCLAAAAAA==.Lylith:BAABLgAECn82AAMcAAkJLBdPEgAIAgAcAAkJLBdPEgAIAgAdAAQJawXT7QBiAAAAAA==.Lyphiandraa:BAAALgAECgEJAQAAAA==.Lysanndra:BAAALgADCgUJBQAAAA==.',
['Lû']='Lûså:BAAALgAECgEJBwAAAA==.',
Ma='Madamcarnage:BAAALgADCgEJAgAAAA==.Maddicollins:BAAALgAECgYJDAABLgAFFAIJDAAJANYbAA==.Magdalena:BAABLgAECn8+AAILAAkJ1w8vCAA/AQALAAkJ1w8vCAA/AQAAAA==.Magehawk:BAAALgAECgUJBQAAAA==.Magicboi:BAAALgAECgYJEQAAAA==.Magikos:BAAALgAECgEJAQAAAA==.Magmaface:BAAALgAECgkJEQAAAA==.Magnólia:BAABLgAECn8tAAICAAkJsyLqCAAjAwACAAkJsyLqCAAjAwAAAA==.Mahito:BAAALgADCgUJBQAAAA==.Maithre:BAAALgAECgIJAwAAAA==.Makima:BAAALgADCgcJCQABLgAFFAQJDQAfAFcXAA==.Manbearcat:BAAALgADCgEJAQAAAA==.Manbearpigg:BAAALgADCgEJAQAAAA==.Manxgina:BAAALgAECgQJBwABLgAFFAUJFgATAKIRAA==.Maribelle:BAAALgAECggJEQABLgAECgkJSQAGAL8jAA==.Marrent:BAAALgADCgcJGQAAAA==.Matlen:BAAALgADCgUJBgAAAA==.Mavelana:BAAALgAECgkJDAAAAA==.Mazeltov:BAABLgAECn8WAAINAAgJPRrNDgAcAgANAAgJPRrNDgAcAgAAAA==.',
Me='Melomel:BAABLgAECn8qAAIjAAgJbRO9EQCZAQAjAAgJbRO9EQCZAQAAAA==.Melonsquezer:BAABLgAECn83AAMQAAkJsh7eBQCOAgAQAAkJsh7eBQCOAgAJAAEJ2RPeMwE9AAAAAA==.Menmei:BAABLgAECn8vAAILAAgJwRUGRQDTAQALAAgJwRUGRQDTAQAAAA==.Mexicanrage:BAAALgADCgQJBAAAAA==.Meygen:BAAALgAECgUJBQAAAA==.',
Mi='Minbyunggyu:BAAALgAECgUJEAAAAA==.Minien:BAABLgAECn82AAMjAAkJdB2dCwD7AQAjAAgJIR2dCwD7AQADAAgJeRjjIwDHAQAAAA==.Minko:BAABLgAECn8rAAILAAkJIhsxIABmAgALAAkJIhsxIABmAgAAAA==.Minore:BAAALgAECgcJCwAAAA==.Mishifu:BAAALgAECgQJBAABLgAFFAQJEQAGAJ0LAA==.',
Mo='Moa:BAAALgAECgEJAQABLgAFFAQJEQAGAJ0LAA==.Modelo:BAAALgAFFAEJAQAAAA==.Molulu:BAAALgADCgcJCwABLgAECgYJIgAGALUKAA==.Monkaholic:BAAALgAECgQJBAAAAA==.Moonshot:BAABLgAECn9cAAIVAAkJKx+mAgC/AgAVAAkJKx+mAgC/AgAAAA==.Morillic:BAABLgAECn8YAAQnAAcJqxhwCwCmAQAnAAcJqxhwCwCmAQAiAAMJrA0MSACWAAAfAAIJMxSCCgFIAAABLgAECggJGgAXABgWAA==.Mouchii:BAAALgAECgEJAQAAAA==.Mousepad:BAAALgAECgEJAQAAAA==.',
Ms='Mstrcrowly:BAABLgAECn8xAAMfAAgJqiBtFgCdAgAfAAgJqiBtFgCdAgAnAAIJvhwqOgBAAAAAAA==.',
Mu='Mustachjones:BAABLgAECn81AAIfAAkJERxUIABjAgAfAAkJERxUIABjAgAAAA==.',
My='Myros:BAABLgAECn86AAMGAAkJfBbeQwAQAgAGAAkJfBbeQwAQAgAOAAEJ8gWrFQApAAAAAA==.',
['Mí']='Mísfire:BAAALgAECgEJAQAAAA==.',
Na='Naakos:BAAALgADCgUJCgAAAA==.Nadiaa:BAAALgADCgYJBgAAAA==.Naih:BAAALgADCgMJAwAAAA==.Nantari:BAAALgAECgcJDAAAAA==.Narestor:BAABLgAECn8YAAIUAAgJHRPBMQDlAQAUAAgJHRPBMQDlAQABLgAFFAYJFQATAOEKAA==.Nasril:BAAALgAECggJEgAAAA==.Nazervis:BAAALgAECgUJBQABLgAFFAgJIgAZAAEeAA==.Nazurend:BAABLgAECn8pAAMGAAkJJRRVRgAIAgAGAAkJJRRVRgAIAgAOAAEJ9QUiFgAmAAAAAA==.',
Nb='Nblock:BAAALgAECgQJBwAAAA==.',
Ne='Nekopunch:BAAALgAFFAEJAgAAAA==.Nemesîs:BAAALgADCgkJGwAAAA==.Nero:BAABLgAECn8nAAIcAAkJTyFYCACoAgAcAAkJTyFYCACoAgAAAA==.Nest:BAAALgADCgYJDQAAAA==.Newhealer:BAAALgADCgEJAQABLgAFFAMJBQAFABkDAA==.',
Ni='Nicholas:BAAALgADCgIJAgAAAA==.Nicorobin:BAABLgAECn8fAAMfAAgJNAUjfQBhAQAfAAgJNAUjfQBhAQAiAAIJywFjZgBDAAAAAA==.Nimuerose:BAAALgAECgEJAQAAAA==.',
No='Noah:BAAALgAECgYJBgAAAA==.Nortree:BAABLgAECn8sAAIPAAgJ3BJoOwCmAQAPAAgJ3BJoOwCmAQAAAA==.Nost:BAABLgAECn8sAAIJAAgJDhyQQAAFAgAJAAgJDhyQQAAFAgAAAA==.Notalock:BAAALgADCgIJAgAAAA==.Notthatbish:BAAALgADCgYJBgAAAA==.Novena:BAAALgAECgQJBAABLgAECgkJLQACALMiAA==.',
Nu='Nulwyrm:BAABLgAECn8sAAMTAAkJQBuAEABjAgATAAkJQBuAEABjAgASAAEJohhQIQBKAAAAAA==.Numira:BAAALgADCgMJAwAAAA==.',
Ny='Nymue:BAAALgAECgMJBAAAAA==.Nyyrivik:BAAALgAECgQJBQAAAA==.',
['Nø']='Nøtrab:BAAALgADCgQJBAAAAA==.',
Oc='Octapie:BAABLgAECn8tAAICAAgJRR+rGACEAgACAAgJRR+rGACEAgAAAA==.',
Oh='Ohitsadragon:BAACLgAFFH8HAAISAAIJSwsqAgB+AAASAAIJSwsqAgB+AAAuAAQKfyAAAhIACAkMFSEIALEBABIACAkMFSEIALEBAAAA.',
On='Ono:BAAALgAECgEJAQAAAA==.',
Or='Oranur:BAAALgADCgIJAgAAAA==.Orclock:BAAALgAECgQJAQABLgAECgYJBgAEAAAAAA==.Oreoscruunit:BAAALgAECgYJBwABLgAECggJEgAEAAAAAA==.',
Ow='Owl:BAABLgAECn8fAAInAAkJAwxUDQBgAQAnAAkJAwxUDQBgAQAAAA==.Owlcatraz:BAACLgAFFH8PAAMPAAUJgwcHLwD2AAAPAAUJgwcHLwD2AAAMAAEJ3gc1GAA8AAAuAAQKfxUAAwwACAlXGv4ZAPwBAAwACAlXGv4ZAPwBAA8ABQknC5Z3AM8AAAAA.',
Pa='Paendrag:BAAALgAECgUJBQAAAA==.Paladinna:BAAALgADCgMJAwAAAA==.Panadarama:BAACLgAFFH8WAAIBAAcJ7BlwCgDqAQABAAcJ7BlwCgDqAQAuAAQKfygAAgEACAkWJWgEAEUDAAEACAkWJWgEAEUDAAAA.Pandmei:BAAALgADCgkJCQAAAA==.Panteragon:BAABLgAECn8rAAIeAAgJgAjtJwBgAQAeAAgJgAjtJwBgAQAAAA==.Pasara:BAAALgADCgQJBAAAAA==.Pashene:BAABLgAECn8nAAILAAgJTAzNbgBjAQALAAgJTAzNbgBjAQAAAA==.',
Pe='Peachyboy:BAAALgADCgMJAwAAAA==.Periwinkle:BAABLgAECn8eAAIWAAgJZg/SKACAAQAWAAgJZg/SKACAAQAAAA==.Persaud:BAACLgAFFH8WAAMnAAUJrRmCCADxAAAfAAUJLxeJSwAwAQAnAAMJwRWCCADxAAAuAAQKfxwAAyIACQkkGtsPANEBACIABwmeEtsPANEBAB8ABQn0Hm1RAKcBAAAA.',
Ph='Phidra:BAABLgAECn9FAAMCAAkJIw/9OwC/AQACAAkJIw/9OwC/AQADAAQJTga/agCYAAAAAA==.Philiia:BAAALgADCgQJBAAAAA==.Philionel:BAAALgADCgYJBgABLgAECgYJIgAGALUKAA==.Phranky:BAAALgAECgEJBAABLgAECggJEgAEAAAAAA==.Phytos:BAAALgAECgEJAQAAAA==.',
Pi='Pixiebrew:BAAALgAECgUJDgAAAA==.Pizzagirl:BAAALgAECgYJEgAAAA==.',
Pl='Plutrax:BAAALgAECgYJEAAAAA==.',
Po='Pokecheck:BAAALgADCgUJBgAAAA==.Power:BAAALgAECgEJAQAAAA==.',
Pr='Predatorc:BAABLgAECn8dAAILAAkJaArHTgB9AQALAAkJaArHTgB9AQAAAA==.Prepotêntê:BAAALgAECgYJCgAAAA==.Primevil:BAABLgAECn8bAAIJAAcJ3xQTCgAGAQAJAAcJ3xQTCgAGAQAAAA==.Primevl:BAABLgAECn8cAAMaAAgJiRbpAACXAQAaAAgJiRbpAACXAQAMAAIJTgn5DABIAAAAAA==.Primévil:BAABLgAECn80AAIdAAkJ4Aw0WQB8AQAdAAkJ4Aw0WQB8AQAAAA==.',
Pu='Puma:BAABLgAECn8VAAQPAAYJjgKksQBWAAAPAAYJjgKksQBWAAAMAAMJjwEQdwBHAAAgAAIJ0gGHjAASAAAAAA==.',
Py='Pymipalmdale:BAAALgAECgEJAQAAAA==.Pyrissa:BAAALgADCgEJAQAAAA==.',
['Pí']='Píp:BAAALgADCggJDQAAAA==.',
Qu='Quarz:BAAALgAECgMJBAAAAA==.Quimmi:BAAALgADCgMJAwAAAA==.Quoternion:BAAALgAECgEJAQABLgAFFAQJBwARACYUAA==.',
Ra='Raden:BAAALgAECgMJBAAAAA==.Raediant:BAAALgAECgUJBwABLgAECgkJHwABAC4VAA==.Raelek:BAAALgAECgQJBAAAAA==.Ragethecage:BAAALgAECgEJAQAAAA==.Raggaemon:BAAALgAFFAEJAQAAAA==.Ragingbanana:BAAALgAECgEJAQAAAA==.Ragsonfire:BAAALgADCgIJAgAAAA==.Rahmonk:BAAALgADCgEJAQAAAA==.Rahvinwulf:BAABLgAECn8lAAMUAAgJPByjHQABAgAUAAgJPByjHQABAgANAAcJrRS7HgA9AQAAAA==.Raquel:BAABLgAECn8jAAICAAkJJQtvRwBkAQACAAkJJQtvRwBkAQAAAA==.Raszageth:BAAALgADCgEJAQAAAA==.Raínbowdash:BAABLgAECn8PAAIeAAgJlxs9DQBSAgAeAAgJlxs9DQBSAgAAAA==.',
Re='Rectaltremor:BAAALgADCgIJAgAAAA==.Rede:BAAALgAECgIJAwAAAA==.Reeyou:BAABLgAECn8YAAIJAAgJWhNjBACXAQAJAAgJWhNjBACXAQABLgAECgkJSgAfADQbAA==.Reign:BAACLgAFFH8RAAIGAAQJnQs7FwAUAQAGAAQJnQs7FwAUAQAuAAQKf00AAgYACQkZHMckAIkCAAYACQkZHMckAIkCAAAA.Reilu:BAAALgADCgIJAgAAAA==.Relieff:BAAALgAECgYJEwAAAA==.Relmin:BAAALgAECgEJAQAAAA==.Rennistus:BAAALgADCgYJBgAAAA==.Revalz:BAAALgAECggJCAAAAA==.Revival:BAAALgAECgYJBwABLgAFFAIJBQAJAGkHAA==.Rewdruid:BAAALgAECgEJAQAAAA==.',
Ri='Rio:BAABLgAECn9IAAIcAAkJSh8/BgDUAgAcAAkJSh8/BgDUAgAAAA==.Ris:BAABLgAECn84AAIGAAkJtB/vGADEAgAGAAkJtB/vGADEAgAAAA==.Riseyyn:BAAALgADCgIJAgAAAA==.',
Ro='Roadzombie:BAAALgADCgMJAwAAAA==.Rockheart:BAAALgAECgMJAwAAAA==.Rockyrogue:BAABLgAECn8eAAIkAAgJDQe0MwAKAQAkAAgJDQe0MwAKAQAAAA==.Roknathar:BAABLgAECn8xAAMVAAkJyCXRAgC3AgAVAAgJwSXRAgC3AgALAAMJ4R4TmgANAQAAAA==.Rolldemort:BAAALgAECgIJAwAAAA==.Ronburrgandy:BAAALgAECgEJAQAAAA==.Ronilf:BAABLgAECn8oAAIkAAkJiBjHFwDcAQAkAAkJiBjHFwDcAQAAAA==.Rono:BAAALgAECgMJAwAAAA==.Rou:BAAALgADCgUJBQAAAA==.Rough:BAAALgADCgEJAQAAAA==.Royda:BAABLgAECn8oAAMXAAkJURxoFAAqAgAXAAkJURxoFAAqAgAWAAIJyhN8iAAnAAAAAA==.',
Ru='Ruitiny:BAAALgAECgcJCAAAAA==.Rukaza:BAAALgAECgEJAQABLgAFFAUJFAAdAEwdAA==.',
Ry='Rygard:BAAALgADCgQJBAAAAA==.',
Sa='Sabrilla:BAAALgAECgQJAwAAAA==.Saerenity:BAAALgAECgMJAwAAAA==.Sahala:BAAALgADCgEJAQAAAA==.Saintlucky:BAAALgADCgYJBgAAAA==.Saintvonzeal:BAAALgAECgEJAQAAAA==.Sakkra:BAAALgADCgQJBAAAAA==.Sangoma:BAAALgAECgUJBQAAAA==.Saphihr:BAAALgADCgYJBgAAAA==.Sapultura:BAAALgAECgEJAQAAAA==.Saxmaster:BAAALgAECgMJAwAAAA==.Sazerac:BAAALgAECgUJEwAAAA==.',
Sc='Scaly:BAAALgAECgEJAQABLgAECgQJBQAEAAAAAA==.',
Se='Sedo:BAABLgAECn8XAAIGAAgJXwXUFgB5AAAGAAgJXwXUFgB5AAAAAA==.Selenis:BAAALgAECgcJDQABLgAECgkJNwAHAJolAA==.',
Sg='Sgtshamrock:BAAALgADCgIJAgAAAA==.',
Sh='Shadowlady:BAAALgAECgEJAQAAAA==.Shadowmonarc:BAAALgAECgYJDAAAAA==.Shadowrealms:BAAALgADCgYJCAAAAA==.Shadygrove:BAAALgAECgEJAQABLgAECgkJLQACALMiAA==.Shamainiac:BAABLgAECn9JAAIDAAkJpRmLEwBQAgADAAkJpRmLEwBQAgAAAA==.Shamania:BAAALgAFFAIJAgABLgAFFAQJCQANAGwcAA==.Shamith:BAAALgAECgcJDgAAAA==.Shammymax:BAAALgADCgkJAQAAAA==.Shaomai:BAACLgAFFH8LAAIDAAQJyhdhJAAHAQADAAQJyhdhJAAHAQAuAAQKfysAAwMACQn1IAYLALACAAMACQn1IAYLALACAAIABAkvDRpzAMMAAAAA.Sharper:BAACLgAFFH8KAAIdAAQJ4xpBOgA8AQAdAAQJ4xpBOgA8AQAuAAQKfxcAAh0ABwlpHGpOAJoBAB0ABwlpHGpOAJoBAAEuAAUUBAkRABkAtRoA.Shep:BAAALgAECgMJAwAAAA==.Sherra:BAAALgADCgIJAgAAAA==.Shi:BAAALgAECgQJBAAAAA==.Shifte:BAABLgAECn8ZAAIaAAgJJxKUAQA3AQAaAAgJJxKUAQA3AQAAAA==.Shiok:BAAALgAECgMJAwAAAA==.Shishkademon:BAAALgAECgIJAgAAAA==.Shocks:BAAALgAECgYJBgABLgAFFAYJIQAJAEkfAA==.Shoknorris:BAAALgADCgkJCQAAAA==.Shâde:BAAALgAECgQJBgAAAA==.',
Si='Siirius:BAAALgAECgcJDAAAAA==.Silverwin:BAABLgAECn8vAAIWAAgJhA/RLQBeAQAWAAgJhA/RLQBeAQAAAA==.',
Sk='Skribbles:BAAALgADCgQJBAAAAA==.',
Sl='Slimage:BAABLgAECn8lAAIoAAkJRRpZAgA5AgAoAAkJRRpZAgA5AgAAAA==.Slushius:BAAALgAECgEJAQAAAA==.',
Sm='Smite:BAAALgAECgQJDgAAAA==.Smitted:BAABLgAECn8ZAAMJAAcJ5A60sgAbAQAJAAcJlwu0sgAbAQAQAAYJ3QpXIwDtAAAAAA==.Smitty:BAABLgAECn8XAAMBAAgJnhWlIgCUAQABAAgJeBSlIgCUAQApAAgJQxD6LABZAQAAAA==.',
Sn='Snakmag:BAAALgAFFAEJAQAAAA==.',
So='Socharis:BAAALgADCgMJAwAAAA==.Sodapops:BAABLgAECn8gAAMhAAYJhBaqAgBnAQAhAAYJhBaqAgBnAQAJAAYJMQ6BygD6AAAAAA==.Sophiaa:BAAALgAECgQJBAAAAA==.Sorn:BAABLgAECn89AAIQAAkJLhQTAQCrAQAQAAkJLhQTAQCrAQAAAA==.',
Sp='Spaarkle:BAAALgAECggJEAAAAA==.Specialheist:BAABLgAECn8bAAIWAAkJ1QKySgC5AAAWAAkJ1QKySgC5AAAAAA==.Spectrehawk:BAAALgAFFAMJAwABLgAFFAQJFgAHANQjAA==.Speçtre:BAACLgAFFH8WAAIHAAQJ1CMRDgCdAQAHAAQJ1CMRDgCdAQAuAAQKfy8AAwcACQkNHU0LAFsCAAcACAk0IE0LAFsCABkAAQn+Bi9mAT0AAAAA.Spins:BAAALgAECgEJAQAAAA==.',
Sr='Srankhunter:BAAALgAECgQJBAAAAA==.',
St='Stallord:BAAALgADCgYJDAAAAA==.Steppin:BAABLgAECn8aAAIXAAgJGBaAIQC6AQAXAAgJGBaAIQC6AQAAAA==.Stonemace:BAAALgADCgYJBgABLgAECgEJAQAEAAAAAA==.Stormglaive:BAABLgAECn8aAAMcAAcJPxU8HQDWAQAcAAcJPxU8HQDWAQAdAAEJUwPt6QAoAAAAAA==.Strikedark:BAAALgAECgEJAQAAAA==.Stupidity:BAABLgAECn8sAAMXAAgJeB42EwA4AgAXAAgJeB42EwA4AgAWAAIJhBe4WAB3AAAAAA==.',
Su='Suldrick:BAAALgADCgkJEAAAAA==.Suppabad:BAABLgAECn9HAAMRAAkJ3x/2BwAdAwARAAkJ3x/2BwAdAwApAAgJRhTHIQChAQAAAA==.Suzäku:BAAALgADCgkJCQAAAA==.',
Sy='Synterra:BAAALgADCgkJCQAAAA==.Syranda:BAAALgAFFAEJAQAAAA==.',
['Sá']='Sákura:BAAALgAECgIJBAAAAA==.',
Ta='Taara:BAAALgAECgIJAwABLgAECgkJSQAGAL8jAA==.Taquìto:BAAALgADCgEJAQAAAA==.Tarysha:BAABLgAECn8qAAIkAAkJvwlpHQCrAQAkAAkJvwlpHQCrAQAAAA==.Tatertotz:BAAALgAECgUJCQAAAA==.Taynav:BAABLgAECn80AAIgAAkJ5xDYHgBXAQAgAAkJ5xDYHgBXAQAAAA==.Tayoma:BAAALgAECgEJAwAAAA==.Tazara:BAAALgAECgUJBwAAAA==.',
Te='Tealth:BAAALgAECgYJBgAAAA==.Ted:BAABLgAECn8kAAIDAAgJghZjJQC+AQADAAgJghZjJQC+AQAAAA==.Tehgermza:BAAALgAECgcJBwAAAA==.Tehgrimza:BAABLgAECn8wAAMfAAkJ/huwAgCuAQAfAAkJ/huwAgCuAQAiAAEJrxCDdAAwAAAAAA==.Teias:BAAALgAECggJCgABLgAFFAUJGgAWAEodAA==.Teka:BAAALgADCgMJAwAAAA==.Temu:BAAALgAECgYJCAABLgAFFAQJDQAfAFcXAA==.Tet:BAACLgAFFH8HAAIPAAMJAQ8lRACjAAAPAAMJAQ8lRACjAAAuAAQKfxkAAg8ACAkyH6QQAMwCAA8ACAkyH6QQAMwCAAAA.Tevia:BAABLgAECn8tAAIKAAkJ4xibDQAOAgAKAAkJ4xibDQAOAgAAAA==.',
Th='Thalip:BAAALgAECgQJBwAAAA==.Thekingheals:BAAALgAECgUJCAABLgAFFAQJBwApAFsVAA==.Thokmay:BAABLgAECn8pAAIpAAkJZxFHIACrAQApAAkJZxFHIACrAQAAAA==.Thorel:BAAALgAECgQJBwAAAA==.Thornar:BAAALgAECgUJBQAAAA==.Thunden:BAAALgAFFAEJAQAAAA==.Thyeth:BAAALgADCgEJAQAAAA==.',
Ti='Tiandrinna:BAABLgAECn8qAAIOAAkJKxxWAgA+AgAOAAkJKxxWAgA+AgAAAA==.Tightywhitey:BAAALgAECggJEAAAAA==.Tigirius:BAAALgAECgQJBAAAAA==.Timkaoss:BAABLgAECn8jAAMPAAcJwRa+AwAdAQAPAAcJwRa+AwAdAQAMAAMJNQfyfQBLAAAAAA==.Timmyjudge:BAAALgAECgYJCAAAAA==.Tinyspoon:BAAALgADCgMJAwAAAA==.',
Tm='Tmagnet:BAABLgAECn8vAAINAAgJxAY5KADyAAANAAgJxAY5KADyAAAAAA==.',
To='Tooshie:BAAALgADCgcJBwAAAA==.Tormin:BAAALgADCgkJFgAAAA==.Torrente:BAAALgADCgEJAQAAAA==.Tourmaline:BAAALgAECgQJCAABLgAECgkJLQACALMiAA==.',
Tr='Treebud:BAAALgADCgkJDAAAAA==.Tritherelyn:BAAALgAECgUJEQAAAA==.Trixterwolf:BAAALgAECgEJAQAAAA==.',
Ts='Tserendolgor:BAAALgADCggJDwAAAA==.',
Tw='Tweedildee:BAACLgAFFH8PAAIGAAMJehGpKwCbAAAGAAMJehGpKwCbAAAuAAQKfy0AAgYACQlcGRQ8ACoCAAYACQlcGRQ8ACoCAAAA.',
Ty='Tygrassar:BAAALgAECgIJAgAAAA==.',
['Tà']='Tàttersail:BAABLgAECn8wAAIWAAkJVh3mCADaAgAWAAkJVh3mCADaAgAAAA==.',
['Tä']='Täd:BAABLgAECn8aAAIfAAgJXRL1CQC5AAAfAAgJXRL1CQC5AAAAAA==.',
Ul='Ulqiuorra:BAAALgADCgQJAQAAAA==.',
Un='Unholycreep:BAAALgAFFAEJAgABLgAFFAQJCQANAGwcAA==.',
Va='Vaelenka:BAAALgADCgMJAwAAAA==.Vaelune:BAAALgAECgYJBgAAAA==.Vahldr:BAAALgAECgQJBQAAAA==.Valdor:BAABLgAECn8jAAMIAAgJ9QvAEwBAAQAIAAgJXAvAEwBAAQAZAAYJPAkn0ADoAAAAAA==.Valeeras:BAAALgADCgUJBQAAAA==.Valeron:BAACLgAFFH8HAAIJAAMJlQ8edADLAAAJAAMJlQ8edADLAAAuAAQKfyIAAgkACAlXHss8ABECAAkACAlXHss8ABECAAAA.Valicous:BAAALgAECgYJEwAAAA==.Valyerian:BAABLgAECn8uAAIUAAgJ5hsOFgCcAgAUAAgJ5hsOFgCcAgAAAA==.Vandalie:BAAALgAECgEJAQABLgAECgkJHgAHAGMiAA==.Vandevoker:BAAALgAECgQJCAABLgAECgkJHgAHAGMiAA==.Vanserra:BAAALgADCgcJEAAAAA==.Varregory:BAAALgADCgUJBAAAAA==.Vaxas:BAABLgAECn8jAAIJAAgJ1h/JMgA1AgAJAAgJ1h/JMgA1AgAAAA==.Vaxasus:BAAALgAECgEJAQAAAA==.Vaylorian:BAABLgAECn8VAAIgAAYJFyACEwDDAQAgAAYJFyACEwDDAQAAAA==.Vaült:BAABLgAECn85AAMhAAkJ8hiGDwCgAgAhAAkJ8hiGDwCgAgAJAAMJPwYbEgFzAAAAAA==.',
Ve='Velystana:BAAALgADCgIJAgAAAA==.Verianna:BAABLgAECn83AAQHAAkJmiVLAQBRAwAHAAkJFSVLAQBRAwAZAAgJZyETMAA/AgAIAAUJlhqRDwB9AQAAAA==.Vexmorphis:BAAALgAECgMJBAABLgAECgkJHgAJAJwSAA==.Vexxis:BAAALgADCgMJAwAAAA==.',
Vi='Vitani:BAAALgAECgEJAQAAAA==.',
Vo='Vodkâshots:BAAALgAECgkJBgAAAA==.Votary:BAAALgAECgQJBAAAAA==.',
Vr='Vraknaar:BAAALgAECgMJAwAAAA==.',
Vt='Vtown:BAAALgAECgMJBwAAAA==.',
Wa='Wadumu:BAABLgAECn8xAAMPAAgJXAwOaQAYAQAPAAYJVg4OaQAYAQAgAAgJlwslLwDwAAAAAA==.Wagwanmist:BAABLgAECn8tAAIRAAgJtBmfHQAsAgARAAgJtBmfHQAsAgAAAA==.Wardrago:BAAALgADCgcJCAAAAA==.Warrdaddy:BAAALgAECgIJAwAAAA==.Warvegas:BAAALgAECgUJDAAAAA==.Warwulf:BAAALgAECgQJBAABLgAECggJJQAUADwcAA==.Water:BAAALgADCgEJAQAAAA==.',
Wi='Willowy:BAABLgAECn9JAAIGAAkJvyMUCwAgAwAGAAkJvyMUCwAgAwAAAA==.',
['Wâ']='Wâlmi:BAABLgAECn8cAAQCAAUJ4hNKeAD1AAACAAUJ4hNKeAD1AAADAAQJ6wjhfQB3AAAjAAEJngq9PwAxAAAAAA==.',
Xa='Xaerius:BAABLgAECn9HAAMUAAkJEBqfEgBeAgAUAAkJEBqfEgBeAgAKAAEJ6wUlhgAjAAAAAA==.Xalatath:BAAALgAECgYJBwAAAA==.Xan:BAABLgAECn8gAAIGAAkJyRfNUQDnAQAGAAkJyRfNUQDnAQAAAA==.Xann:BAAALgAECgIJAgAAAA==.Xannen:BAAALgADCgkJCQAAAA==.Xantharr:BAAALgADCgMJAwAAAA==.Xantyr:BAABLgAECn8ZAAMGAAgJ4yBkIwCPAgAGAAgJ6h9kIwCPAgAoAAIJyCAeDAC9AAAAAA==.Xashadin:BAAALgAECgcJBwAAAA==.Xashae:BAAALgADCgcJDwAAAA==.',
Xe='Xenocidal:BAABLgAECn8YAAIGAAcJJiNIPQCCAgAGAAcJJiNIPQCCAgAAAA==.',
Xo='Xog:BAAALgAECgIJAgAAAA==.',
Ya='Yarman:BAABLgAECn8vAAIBAAgJgBc9HgC0AQABAAgJgBc9HgC0AQAAAA==.',
Ye='Yeaforpie:BAABLgAECn8yAAMnAAkJ3xSDAADgAQAnAAkJ3xSDAADgAQAfAAgJ8Q++XACIAQAAAA==.Yervant:BAAALgAECgQJBAAAAA==.Yesthatbish:BAABLgAECn8YAAIhAAgJ7BQPLACxAQAhAAgJ7BQPLACxAQAAAA==.',
Yo='Yoshial:BAABLgAECn8iAAIGAAYJtQqr2ADlAAAGAAYJtQqr2ADlAAAAAA==.Youfemaledog:BAAALgADCgEJAQAAAA==.',
Za='Zadoc:BAAALgADCgcJGwAAAA==.Zano:BAACLgAFFH8FAAIXAAMJlhLAIwDXAAAXAAMJlhLAIwDXAAAuAAQKfz4AAxcACQlDG1cNAH4CABcACQlDG1cNAH4CABgABgk8DQhCAAIBAAAA.',
Ze='Zealins:BAAALgAECgUJCQAAAA==.Zenrek:BAAALgADCgEJAQAAAA==.Zenrekt:BAAALgADCgMJBAAAAA==.Zerastar:BAAALgAECgQJBAAAAA==.Zeuhl:BAAALgAECgcJCwAAAA==.',
Zi='Zilver:BAAALgADCgEJAQAAAA==.Zirou:BAAALgAFFAIJBAABLgAFFAMJCQAeACMhAA==.Ziv:BAACLgAFFH8aAAIPAAUJ4xkwBgBMAQAPAAUJ4xkwBgBMAQAuAAQKfzYAAg8ACQkqINEIACsDAA8ACQkqINEIACsDAAEuAAUUAwkJAB4AIyEA.Ziyn:BAACLgAFFH8JAAIeAAMJIyG7FwAUAQAeAAMJIyG7FwAUAQAuAAQKfxgAAx4ACQk+HmgHAKgCAB4ACQk+HmgHAKgCAAsABgmuGnJ9AEQBAAAA.',
Zo='Zoda:BAAALgAECgIJAwAAAA==.',
Zx='Zxno:BAAALgAECgEJAQAAAA==.Zxolgarai:BAAALgAECgMJAwAAAA==.',
['Ôa']='Ôath:BAAALgAECgEJAQAAAA==.',
['Öw']='Öwlbeback:BAAALgADCgYJBgAAAA==.',
['Ÿe']='Ÿeñnefer:BAAALgADCgIJAgAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
