import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator';
import { AuthenticatedUser, JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
  CreateGoalDto,
  CreateHabitDto,
  CreateReflectionDto,
  UpdateGoalDto,
} from './dto/growth.dto';
import {
  GoalResponse,
  HabitResponse,
  ReflectionResponse,
} from './growth.mapper';
import { GrowthService } from './growth.service';

/**
 * Personal-development endpoints (`/v1/growth/*`): goals, habits, reflections.
 * All require a Bearer token; the owner comes from the token.
 */
@UseGuards(JwtAuthGuard)
@Controller('growth')
export class GrowthController {
  constructor(private readonly growth: GrowthService) {}

  @Get('goals')
  listGoals(@CurrentUser() user: AuthenticatedUser): Promise<GoalResponse[]> {
    return this.growth.listGoals(user.id);
  }

  @Post('goals')
  createGoal(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateGoalDto,
  ): Promise<GoalResponse> {
    return this.growth.createGoal(user.id, dto);
  }

  @Patch('goals/:id')
  updateGoal(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateGoalDto,
  ): Promise<GoalResponse> {
    return this.growth.updateGoal(user.id, id, dto);
  }

  @Delete('goals/:id')
  @HttpCode(204)
  async removeGoal(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<void> {
    await this.growth.remove(user.id, id, 'goal');
  }

  @Get('habits')
  listHabits(@CurrentUser() user: AuthenticatedUser): Promise<HabitResponse[]> {
    return this.growth.listHabits(user.id);
  }

  @Post('habits')
  createHabit(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateHabitDto,
  ): Promise<HabitResponse> {
    return this.growth.createHabit(user.id, dto);
  }

  /** Toggle today's completion for a habit. */
  @Post('habits/:id/check')
  checkHabit(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<HabitResponse> {
    return this.growth.toggleHabitToday(user.id, id);
  }

  @Delete('habits/:id')
  @HttpCode(204)
  async removeHabit(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<void> {
    await this.growth.remove(user.id, id, 'habit');
  }

  @Get('reflections')
  listReflections(
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<ReflectionResponse[]> {
    return this.growth.listReflections(user.id);
  }

  @Post('reflections')
  createReflection(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateReflectionDto,
  ): Promise<ReflectionResponse> {
    return this.growth.createReflection(user.id, dto);
  }

  @Delete('reflections/:id')
  @HttpCode(204)
  async removeReflection(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id', ParseUUIDPipe) id: string,
  ): Promise<void> {
    await this.growth.remove(user.id, id, 'reflection');
  }
}
